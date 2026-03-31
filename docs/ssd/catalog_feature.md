# FEATURE: Catálogo de Conceptos

## Objetivo
Permitir crear, editar e importar conceptos de obra con atributos dinámicos.

## Alcance
- Gestión de universos
- Conceptos base
- Atributos y opciones
- Importación CSV

## Reglas
- No duplicar conceptos
- Atributos deben ser reutilizables
- Cada concepto pertenece a un universo
- No lógica de negocio en UI

## Estructura

Frontend:
- Pantalla catálogo
- Formularios
- Importador CSV

Backend (Supabase):
- universes
- concept_templates
- concept_attributes
- attribute_options

## Riesgos
- duplicación de atributos
- inconsistencia en CSV