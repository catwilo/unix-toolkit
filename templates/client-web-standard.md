# Estandar de calidad -- repos cliente web (v1)

> Plantilla de referencia para ut new <repo> client '<desc>'.
> Aplicar manualmente al iniciar un repo con tag client.
> Este documento mejora por versiones: cada aprendizaje de un proyecto
> real se incorpora aqui antes del siguiente repo cliente.

Origen: analisis comparativo de 6 repos propios (BaquiaRaudal como
referencia de madurez) + Google Engineering Practices.

## 1. Gobierno de repo
- README.md -- que es, como instalar, como contribuir
- ARCHITECTURE.md -- decisiones, limites, flujo de datos
- REQUIREMENTS.md -- dependencias, versiones minimas
- CONTRIBUTING.md -- flujo de trabajo, convencion de commits

## 2. Arquitectura por capas verificada en CI
- Hexagonal por dominio: domain -> application -> infrastructure -> interface
- Dependencia siempre hacia adentro; verificado con go-arch-lint (Go) o equivalente (JS/TS)
- Comunicacion entre dominios via eventos internos, nunca imports directos

## 3. Contrato de API como fuente unica de verdad
- OpenAPI 3.1 en api/openapi.yaml
- Cliente TS generado automaticamente, nunca escrito a mano
- CI valida que el contrato este sincronizado con la implementacion

## 4. Linters agresivos por lenguaje
Go: golangci-lint con bodyclose, sqlclosecheck, contextcheck, errorlint, nilerr, gosec, noctx
JS/TS: Biome o ESLint con reglas en error (no warning): noUnusedVariables, useConst, useImportType

## 5. Definition of Done (explicita)
- Compila sin errores
- Lint limpio (cero warnings)
- Tests nuevos + cobertura razonable en codigo nuevo
- Verificacion arquitectonica en cero (arch-lint)
- Contrato OpenAPI sincronizado
- CI verde
- Documentacion actualizada
- Tarea cerrada en miko

## 6. Seguridad como checklist
- Rate limiting en endpoints publicos
- Limite de tamano de body
- Timeouts explicitos (lectura/escritura)
- Validacion de input obligatoria
- Secrets fuera del repo (.env.example + permisos 600)
- Prepared statements (si SQL), soft deletes
- JWT en cookies httpOnly (si auth), CORS explicito (no *)
- Backups automaticos con retencion

## 7. Nada especulativo
- Resolver el problema de ahora, no el que podria llegar
- Fases P1-P4: P1 es MVP validado; no se toca P2 hasta que P1 este en produccion

## 8. Convencion de commits
type(scope): descripcion   (imperativo, <=60 caracteres)

## Puntos debiles detectados en repos previos (no repetir)
- Errores ignorados sin manejo ni validacion basica (prestamos-lc)
- Sitios estaticos sin lint/tests/CI (microcemento-site, sibarita-site, districarnesVera)
- Versionado inconsistente entre repos sin politica de actualizacion

## Checklist pre-dev (repo cliente nuevo)
- [ ] Repo creado via ut new <repo> client '<desc>'
- [ ] README con instrucciones de setup
- [ ] Dependencias minimas declaradas
- [ ] .gitignore y .env.example
- [ ] Linter configurado (Biome/ESLint o golangci-lint)
- [ ] CI: workflow de lint + test en cada push
- [ ] Primera tarea en miko: "Definir estructura basica"
- [ ] Branch protection en main (CI verde + 1 review)

## Historial de versiones
- v1 (2026-08-25): version inicial, basada en analisis de BaquiaRaudal + Google Eng Practices. Aplicada por primera vez en VocesDelLlano.
