package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"
)

// HostResources holds a point-in-time snapshot of available system resources.
type HostResources struct {
	TotalRAM     uint64  `json:"ram_total_mb"`
	AvailableRAM uint64  `json:"ram_available_mb"`
	TotalCPU     int     `json:"cpu_cores"`
	CPUIdle      float64 `json:"cpu_idle_pct"`
	LoadAvg1m    float64 `json:"load_avg_1m"`
	SwapFree     uint64  `json:"swap_free_mb"`
}

// AllocationTarget is the per-component resource assignment.
type AllocationTarget struct {
	BrowserWorkerRAM string `json:"browser_ram"`
	BrowserWorkerCPU string `json:"browser_cpu"`
	OrchestratorRAM  string `json:"orchestrator_ram"`
	MemoryEngineRAM  string `json:"memory_engine_ram"`
	CompressorRAM    string `json:"compressor_ram"`
}

// SentinelState tracks the current state of all managed allocations.
type SentinelState struct {
	Resources  HostResources    `json:"resources"`
	Allocation AllocationTarget `json:"allocation"`
	ActiveSess int              `json:"active_sessions"`
	Pressure   bool             `json:"memory_pressure"`
}

var state SentinelState

func readMeminfo() (totalKB, availableKB, swapFreeKB uint64) {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		log.Printf("WARN: cannot read /proc/meminfo: %v", err)
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		val, _ := strconv.ParseUint(fields[1], 10, 64)
		switch fields[0] {
		case "MemTotal:":
			totalKB = val
		case "MemAvailable:":
			availableKB = val
		case "SwapFree:":
			swapFreeKB = val
		}
	}
	return
}

// readCPUStat returns (idle ticks, total ticks) from /proc/stat.
func readCPUStat() (idle, total uint64) {
	data, err := os.ReadFile("/proc/stat")
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(data), "\n") {
		if !strings.HasPrefix(line, "cpu ") {
			continue
		}
		fields := strings.Fields(line)
		// fields: cpu user nice system idle iowait irq softirq steal
		for i, f := range fields[1:] {
			v, _ := strconv.ParseUint(f, 10, 64)
			total += v
			if i == 3 { // idle column
				idle = v
			}
		}
		return
	}
	return
}

func readLoadAvg() float64 {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0
	}
	v, _ := strconv.ParseFloat(fields[0], 64)
	return v
}

// sampleCPUIdle sleeps 500ms between two /proc/stat reads to calculate idle %.
func sampleCPUIdle() float64 {
	idle1, total1 := readCPUStat()
	time.Sleep(500 * time.Millisecond)
	idle2, total2 := readCPUStat()
	deltaTotal := total2 - total1
	deltaIdle := idle2 - idle1
	if deltaTotal == 0 {
		return 100
	}
	return float64(deltaIdle) / float64(deltaTotal) * 100
}

// computeAllocation derives per-component limits from available resources.
// Rule: use at most 70 % of MemAvailable; reserve 15 % host floor + 15 % buffer.
func computeAllocation(r HostResources, activeSessions int) AllocationTarget {
	usableRAMMB := float64(r.AvailableRAM) * 0.70
	usableCPU := float64(r.TotalCPU) * (r.CPUIdle / 100.0) * 0.70

	// Clamp CPU to at least 0.5 cores total
	if usableCPU < 0.5 {
		usableCPU = 0.5
	}

	// Distribution by priority: browser > memory > orchestrator > compressor
	browserRAM := usableRAMMB * 0.55
	memEngRAM := usableRAMMB * 0.25
	orchRAM := usableRAMMB * 0.10
	compRAM := usableRAMMB * 0.10

	// Enforce minimums
	if memEngRAM < 256 {
		memEngRAM = 256
	}
	if orchRAM < 128 {
		orchRAM = 128
	}
	if compRAM < 64 {
		compRAM = 64
	}

	// Per-worker browser budget
	workers := activeSessions
	if workers < 1 {
		workers = 1
	}
	perBrowserRAM := browserRAM / float64(workers)
	perBrowserCPU := (usableCPU * 0.7) / float64(workers)

	return AllocationTarget{
		BrowserWorkerRAM: fmt.Sprintf("%.0fm", perBrowserRAM),
		BrowserWorkerCPU: fmt.Sprintf("%.2f", perBrowserCPU),
		OrchestratorRAM:  fmt.Sprintf("%.0fm", orchRAM),
		MemoryEngineRAM:  fmt.Sprintf("%.0fm", memEngRAM),
		CompressorRAM:    fmt.Sprintf("%.0fm", compRAM),
	}
}

// measure does one full resource poll and updates global state.
func measure() {
	totalKB, availKB, swapFreeKB := readMeminfo()
	idlePct := sampleCPUIdle()

	r := HostResources{
		TotalRAM:     totalKB / 1024,
		AvailableRAM: availKB / 1024,
		TotalCPU:     runtime.NumCPU(),
		CPUIdle:      idlePct,
		LoadAvg1m:    readLoadAvg(),
		SwapFree:     swapFreeKB / 1024,
	}

	state.Resources = r
	state.Allocation = computeAllocation(r, state.ActiveSess)
	state.Pressure = r.AvailableRAM < 500
}

// handleConn processes a single client connection on the Unix socket.
func handleConn(conn net.Conn) {
	defer conn.Close()

	dec := json.NewDecoder(conn)
	enc := json.NewEncoder(conn)

	var req map[string]string
	if err := dec.Decode(&req); err != nil {
		return
	}

	switch req["cmd"] {
	case "status":
		enc.Encode(state)

	case "allocate":
		state.ActiveSess++
		measure()
		enc.Encode(map[string]interface{}{
			"ok":         true,
			"allocation": state.Allocation,
		})

	case "release":
		if state.ActiveSess > 0 {
			state.ActiveSess--
		}
		measure()
		enc.Encode(map[string]bool{"ok": true})

	case "emergency_throttle":
		state.ActiveSess = 0
		enc.Encode(map[string]bool{"ok": true, "throttled": true})

	default:
		enc.Encode(map[string]string{"error": "unknown command"})
	}
}

func intervalFor() time.Duration {
	if state.ActiveSess == 0 {
		return 10 * time.Second
	}
	if state.Pressure {
		return 1 * time.Second
	}
	return 3 * time.Second
}

func main() {
	sockPath := "/tmp/aicli/sentinel.sock"
	os.MkdirAll("/tmp/aicli", 0700)
	os.Remove(sockPath)

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		log.Fatalf("sentinel: cannot bind socket: %v", err)
	}
	os.Chmod(sockPath, 0600)

	// Initial measurement
	measure()
	log.Printf("sentinel: started — %dMB available, %d cores, %.1f%% idle",
		state.Resources.AvailableRAM, state.Resources.TotalCPU, state.Resources.CPUIdle)

	// Background polling goroutine
	go func() {
		for {
			time.Sleep(intervalFor())
			measure()
			if state.Pressure {
				log.Printf("WARN: memory pressure — only %dMB available", state.Resources.AvailableRAM)
			}
		}
	}()

	// Accept loop
	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("sentinel: accept error: %v", err)
			continue
		}
		go handleConn(conn)
	}
}
