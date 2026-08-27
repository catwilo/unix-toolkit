# Estandar de calidad -- repos cliente web (v1)

> Plantilla de referencia para ut new <repo> client '<desc>'.
> Aplicar manualmente al iniciar un repo con tag client.
> Este documento mejora por versiones: cada aprendizaje de un proyecto
> real se incorpora aqui antes del siguiente repo cliente.

Origen: analisis comparativo de 6 repos propios (BaquiaRaudal como
referencia de madurez) + Google Engineering Practices.

## 0. Perfiles -- elegir antes de aplicar el resto del estandar
No todo repo cliente necesita backend. Elegir el perfil segun el problema
real, nunca por defecto al mas complejo (ver seccion 7, Nada especulativo).

**Perfil A -- Estatico simple** (sitios institucionales, portafolios,
landing pages, contenido editado con baja frecuencia, sin logica de
negocio ni datos transaccionales):
- Sin backend, sin base de datos.
- Contenido en Markdown/JSON versionado en el propio repo.
- Stack: Vite + React + TypeScript, sin SSR salvo necesidad probada.
- Deploy: Vercel o Netlify (gratis, sin servidor que mantener).
- Las secciones 2 y 3 (arquitectura hexagonal, contrato OpenAPI) NO
  aplican a este perfil -- no hay dominios de negocio ni API propia.

**Perfil B -- Full-stack con backend** (logica de negocio, datos
transaccionales, multiples usuarios/roles, integraciones):
- Aplica el estandar completo: secciones 1 a 8 sin excepcion.
- Referencia de madurez: BaquiaRaudal (arquitectura hexagonal,
  multi-tenant, OpenAPI como contrato).

Documentar el perfil elegido y por que, en el ARCHITECTURE.md propio del
repo -- ese documento no repite este estandar generico, aplica sus
decisiones concretas.

## 1. Gobierno de repo
- README.md -- que es, como instalar, como contribuir
- ARCHITECTURE.md -- decisiones, limites, flujo de datos (concreto del
  repo, nunca una copia de este estandar generico)
- REQUIREMENTS.md -- dependencias, versiones minimas
- CONTRIBUTING.md -- flujo de trabajo, convencion de commits

## 2. Arquitectura por capas verificada en CI (solo Perfil B)
- Hexagonal por dominio: domain -> application -> infrastructure -> interface
- Dependencia siempre hacia adentro; verificado con go-arch-lint (Go) o equivalente (JS/TS)
- Comunicacion entre dominios via eventos internos, nunca imports directos

## 3. Contrato de API como fuente unica de verdad (solo Perfil B)
- OpenAPI 3.1 en api/openapi.yaml
- Cliente TS generado automaticamente, nunca escrito a mano
- CI valida que el contrato este sincronizado con la implementacion

## 3b. Organizacion de estilos/CSS (ambos perfiles)
- CSS Modules: un archivo <Componente>.module.css por componente,
  scope automatico, sin fugas de estilos entre componentes.
- Nunca CSS global salvo variables/reset minimo en un unico
  styles/globals.css (tokens: colores, tipografia, espaciado).
- Un componente y su .module.css viven en la misma carpeta -- nombre
  del componente y nombre del modulo deben coincidir exactamente.
- Nombres de clase dentro del modulo: descriptivos de la funcion visual
  (ej. .card, .cardTitle), nunca genericos (.box1, .wrapper2).
- Jerarquia de carpetas refleja jerarquia visual: components/ui/ para
  atomos reutilizables (Button, Card), components/layout/ para
  estructura de pagina (Header, Footer), pages/ para una carpeta por
  ruta del sitio.

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
