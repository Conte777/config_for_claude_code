# Review Report Template

Шаблон отчёта о code review.

---

## Сводка проверки

**Дата:** {date}
**Ревьюер:** Claude Code
**Язык/Фреймворк:** {language} / {framework}

Проанализировано **{file_count}** файл(ов).

| Уровень | Количество |
|---------|------------|
| 🔴 Critical | {critical_count} |
| 🟠 High | {high_count} |
| 🔵 Low | {low_count} |

---

## Критические проблемы 🔴

> Требуют немедленного исправления. Security vulnerabilities, data loss, production crash.

### 1. {issue_title}

**Файл:** `{file_path}:{line_number}`

**Проблема:**
{issue_description}

**Код:**
```{language}
{problematic_code}
```

**Рекомендация:**
{recommendation}

**Исправленный код:**
```{language}
{fixed_code}
```

---

## Серьёзные проблемы 🟠

> Должны быть исправлены до merge. Race conditions, resource leaks, significant bugs, blocking in async.

### 1. {issue_title}

**Файл:** `{file_path}:{line_number}`

**Проблема:**
{issue_description}

**Рекомендация:**
{recommendation}

---

## Замечания 🔵

> По возможности исправить. Performance issues, code smells, minor improvements.

### 1. {issue_title}

**Файл:** `{file_path}:{line_number}`

**Замечание:**
{issue_description}

**Рекомендация:**
{recommendation}

---

## Дополнительные ресурсы

- {relevant_documentation_link}
- {best_practices_guide}

---

*Отчёт сгенерирован автоматически с помощью code-review skill.*
