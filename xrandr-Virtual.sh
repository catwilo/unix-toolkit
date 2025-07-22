#!/bin/bash

#cvt 1366 768 60 // X Y frecuenciaHz

xrandr --newmode "1366x768"  40.00  1366 1408 1520 1664  768 771 774 798 -hsync +vsync
#xrandr --newmode "1366x768"  85.25  1366 1440 1576 1784  768 771 781 798 -hsync +vsync

xrandr --addmode VIRTUAL1 "1366x768"
xrandr --output VIRTUAL1 --mode "1366x768" --right-of DP2

vncviewer e430:0


