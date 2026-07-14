# Prompt para Claude — Sistema de diseño CBUM

Crea el sistema de diseño completo de **CBUM**, una app iOS de coaching de gimnasio y nutrición para uso personal serio. Entrégalo como una guía visual interactiva (HTML) con todos los tokens y los componentes renderizados con datos de ejemplo reales.

## Contexto del producto

CBUM es un AI coach de hipertrofia basado en evidencia (estilo Built with Science). El usuario loguea entrenos en el gym (peso, reps, RIR) y comidas por foto vía Claude; todo se guarda en su base de datos y Apple Health. El principio rector del producto es la **precisión**: nada de estimaciones vagas — cada número tiene fuente y confianza. La app tiene 5 pantallas: Hoy (anillos de macros, peso-tendencia, TDEE, entreno del día), Sesión de entreno (logging de sets con rest timer), Nutrición (meals con badge de fuente), Progreso (e1RM, volumen por músculo), Ajustes.

## Dirección visual

- **Colores**: fondo y base **negro puro (#000000)**; color secundario/acento **#F5F5DC** (beige hueso). Casi monocromo, alto contraste, dark-mode-only. Define también: grises intermedios para superficies y bordes, un color de éxito/PR, uno de alerta, y uno para "dato estimado" (baja confianza) — todos derivados o compatibles con la paleta negro/beige.
- **Tipografía agresiva**: esta app es para aplastar metas de gimnasio. Headers en display **condensada, ultra-bold, uppercase, tracking apretado** (estilo cartel de powerlifting / marca deportiva). Números grandes protagonistas — el peso, las reps y el e1RM se leen desde un metro de distancia con el teléfono en el piso. Cuerpo de texto limpio y legible para no sacrificar la precisión. Especifica familias concretas (con alternativas de SF Pro / system para iOS), escala tipográfica completa y pesos.
- **Sensación**: disciplina, intensidad, cero decoración gratuita. Bordes duros o radios mínimos, mucho espacio negro, el beige se usa quirúrgicamente para lo que importa (CTAs, PRs, números clave).

## Tokens a definir

Paleta completa con usos, escala tipográfica, espaciado (grid 4pt), radios, iconografía (estilo), estados (pressed/disabled), y reglas de movimiento (transiciones cortas y secas, celebración de PR).

## Los 12 componentes básicos (obligatorios, renderízalos todos)

1. **Tab bar + header de pantalla** — navegación de las 5 secciones, título display uppercase.
2. **Botón primario / secundario / destructivo** — el primario es el CTA "EMPEZAR ENTRENO".
3. **Anillo de macros** — kcal + proteína/carbos/grasa consumidos vs objetivo, números al centro.
4. **Stat card** — métrica grande + label + delta (ej. peso-tendencia 82.4kg ▼0.3/sem) con estado opcional "CALIBRANDO".
5. **Exercise card (objetivo del día)** — "PRESS BANCA — 4×8 @ RIR 2 — sugerido 80kg", con acceso a sustituir.
6. **Set logger row** — el componente estrella: steppers de peso y reps + selector RIR, guardable con el pulgar, usable a mitad de serie con manos sudadas. Estados: pendiente, guardado, PR.
7. **Selector RIR** — segmented 0–5, tap único, etiquetas claras.
8. **Rest timer** — countdown gigante, arranca solo al guardar set, +30s/skip.
9. **Badge de fuente/confianza** — ⚖️ pesado / 🏷 etiqueta / 📷 estimado, con variante de baja confianza.
10. **Meal row** — comida con macros, hora, badge de fuente, editable.
11. **Gráfico de línea** — e1RM y peso-tendencia en el tiempo (línea beige sobre negro, punto de PR marcado).
12. **Barras de volumen semanal** — sets efectivos por grupo muscular vs rango objetivo (zona objetivo visible).

Extra si cabe: toast de celebración de PR y resumen de fin de sesión.

Para cada componente: anatomía, variantes, estados y reglas de uso. Todo renderizado con datos realistas de gym (kg, RIR, macros), no lorem ipsum.
