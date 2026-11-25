# Personal AI Library

**A reusable library of practical AI agent skills, runbooks, checklists, templates, and helper scripts for Codex.**

Personal AI Library helps an AI coding agent move from a broad request to a structured workflow: investigation, code review, debugging, development, deployment, research, or document preparation. Instead of rebuilding the same process for every project, the agent can select a relevant skill and load its supporting references when needed.

> **Current release:** 23 skills. The collection is actively maintained. A documented workflow is not a guarantee that it has been tested in every project, environment, or service configuration.

**Languages:** [English](#english) | [Русский](#русский)

---

## English

### What is included

Each skill is stored in its own directory under `skills/<skill-name>/`. A skill may include:

- **`SKILL.md`** — the skill's purpose, when to use it, and its core instructions.
- **`references/`** — detailed runbooks, checklists, procedures, templates, and supporting documentation.
- **`scripts/`** — helper scripts where automation is useful.

Supporting references are loaded only when relevant. This keeps the initial instructions focused and avoids sending the agent the entire documentation set for every task.

### Skill areas

The current collection contains 23 skills across six areas:

| Area | Examples of covered tasks |
|---|---|
| **Software development** | Python development, AST-based code audits, import and startup checks, web development, VPS/DevOps, APIs and automation |
| **Platforms and messaging** | Telegram and MAX bots, GitHub repositories and portfolios, social media workflows, content planning |
| **Cryptocurrency and trading systems** | Crypto research, market-regime analysis, futures risk calculations, trading-bot audits |
| **Business and marketing** | Product positioning, marketing copy, SEO audits, Kwork order workflows, fact-checking and source verification |
| **Images and marketplaces** | Product photo processing, marketplace listing images and listing preparation |
| **Spreadsheets and documents** | Google Sheets, Apps Script, Word, PDF, Excel, and presentations |

Browse the complete list and each skill's purpose: [English skill catalog](CATALOG-EN.md) · [Русский каталог](CATALOG.md).

### Installation on Windows

**Requirements:** Windows 10 or 11 and Windows PowerShell 5.1 or PowerShell 7. Python is not required for installation.

1. Open the [GitHub repository](https://github.com/HOADF/Personal-AI-Library).
2. Select **Code → Download ZIP**, then extract the archive.
3. Open PowerShell in the extracted repository folder.
4. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

The installer copies the skills to the current user's skills directory:

```text
%USERPROFILE%\.agents\skills\
```

Restart Codex if it was already running.

### Updating the library

Download and extract the latest repository version, open PowerShell in the new folder, and run:

```powershell
.\install.ps1 -Force
```

Without `-Force`, existing skill folders are skipped. With `-Force`, files currently supplied by the library are replaced with repository versions. The installer tracks managed files and their SHA256 hashes in `.personal-ai-library-manifest.json`. An obsolete file is deleted only if its contents still match the last installed hash; locally modified obsolete files and untracked user files are preserved. If no manifest exists, unknown files are not deleted automatically.

### Installer and security notes

`install.ps1` copies skill files to the destination directory. It does not install Python packages, connect to APIs, execute skill scripts, or require access tokens or passwords.

You can inspect the installer and skill files before running them. As with any downloaded code or instructions, review scripts and external dependencies before using them in a production environment.

### Validation and tests

Python 3.9 or newer is required to run the repository validation and Python tests. CI checks compatibility on Python 3.9, 3.12, and 3.14. No third-party packages are required for the basic validation:

```powershell
python .\validate_skills.py
```

Run the Python tests:

```powershell
python -m unittest discover -s tests -v
```

Run the Windows installer tests from PowerShell:

```powershell
.\tests\test_install.ps1
```

A repeatable manual evaluation protocol with five pilot Skills is available in [tests/SKILL-EVALUATION.md](tests/SKILL-EVALUATION.md).

GitHub Actions runs automated checks on pushes and pull requests. The workflow validates the skill structure and tests the installer on Windows PowerShell 5.1 and PowerShell 7.

These checks cover repository structure, local references, the syntax of checked Python files, and installer behavior in test scenarios. They do **not** prove that every workflow is suitable for every project, that external services are available, or that an AI agent will always produce a correct result.

### Project principles

- **Practicality:** skills should solve real, distinct tasks.
- **Accuracy:** distinguish verified facts from assumptions and unverified information.
- **Structured work:** investigate first, propose a plan, then make changes.
- **Safety:** do not expose secrets or perform irreversible actions without authorization.
- **Cost awareness:** do not use paid APIs or services without approval.
- **Source review:** check the origin, license, dependencies, scripts, and compatibility of third-party materials.
- **Transparency:** record sources and limitations; never claim checks or tests that were not performed.

General agent guidance is available in [AGENTS.md](AGENTS.md). Source notes and selection criteria are documented in [SOURCES.md](SOURCES.md). Repository changes are recorded in [CHANGELOG.md](CHANGELOG.md).

### Repository structure

```text
Personal-AI-Library/
├── AGENTS.md
├── CATALOG.md
├── CATALOG-EN.md
├── CHANGELOG.md
├── SOURCES.md
├── README.md
├── LICENSE
├── LICENSE-CODE
├── LICENSE-CONTENT
├── install.ps1
├── validate_skills.py
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md
│       ├── references/
│       └── scripts/
├── tests/
└── .github/workflows/
```

### Feedback and contributions

Found an error, an outdated instruction, or have an idea for a useful skill? Open a [GitHub Issue](https://github.com/HOADF/Personal-AI-Library/issues). Include the task, expected behavior, and relevant sources where possible.

New skills should solve a distinct practical problem, avoid duplicating existing skills, and respect the licenses of third-party materials.

### Licensing

This repository uses separate licenses for software and written content:

- **Installer, validator, tests, workflow, and designated helper scripts:** [MIT License](LICENSE-CODE).
- **Skills, instructions, runbooks, checklists, templates, and documentation:** [CC BY-NC-SA 4.0](LICENSE-CONTENT).

The written materials may be shared and adapted for non-commercial purposes with attribution. Shared adaptations must use the same or a compatible license. Commercial use of these written materials requires separate written permission from the rights holder.

Read the license files for the exact scope and conditions. Third-party materials, if included, remain subject to their own license terms.

---

## Русский

### Что это за проект

**Personal AI Library** — библиотека готовых навыков (Skills), инструкций и рабочих методик для Codex.

Она помогает ИИ-агенту переходить от общей задачи к конкретному порядку действий: исследованию, аудиту кода, отладке, разработке, развёртыванию, анализу информации или подготовке документов. Вместо того чтобы каждый раз собирать процесс с нуля, агент выбирает подходящий навык и при необходимости читает дополнительные материалы.

> **Текущая версия:** 23 навыка. Библиотека развивается. Наличие инструкции не означает, что описанный процесс проверен на всех проектах, системах и конфигурациях сервисов.

### Что входит в библиотеку

Каждый навык находится в отдельной папке `skills/<skill-name>/` и может содержать:

- **`SKILL.md`** — назначение навыка, условия его применения и основные инструкции.
- **`references/`** — подробные рабочие инструкции (runbooks), чек-листы, алгоритмы, шаблоны и справочные материалы.
- **`scripts/`** — вспомогательные скрипты, если автоматизация действительно полезна.

Дополнительные материалы загружаются по мере необходимости. Это позволяет не передавать агенту всю документацию при каждой задаче.

### Направления библиотеки

Сейчас в библиотеке 23 навыка по шести направлениям:

| Направление | Примеры задач |
|---|---|
| **Программирование и разработка** | Python, AST-аудит кода, проверка импортов и запуска, веб-разработка, VPS/DevOps, API и автоматизация |
| **Площадки и мессенджеры** | Telegram- и MAX-боты, GitHub-репозитории и портфолио, социальные сети, планирование контента |
| **Криптовалюта и торговые системы** | Исследование криптовалют, анализ режима рынка, расчёт риска фьючерсных позиций, аудит торговых ботов |
| **Бизнес и маркетинг** | Позиционирование продукта, рекламные тексты, SEO-аудит, работа с заказами Kwork, проверка фактов и источников |
| **Изображения и маркетплейсы** | Обработка фотографий товаров, подготовка изображений и карточек объявлений |
| **Таблицы и документы** | Google Sheets, Apps Script, Word, PDF, Excel и презентации |

Полный список навыков и описание каждого: [каталог на русском](CATALOG.md) · [English catalog](CATALOG-EN.md).

### Установка на Windows

**Требования:** Windows 10/11 и Windows PowerShell 5.1 или PowerShell 7. Для установки Python не требуется.

1. Откройте [страницу репозитория на GitHub](https://github.com/HOADF/Personal-AI-Library).
2. Нажмите **Code → Download ZIP** и распакуйте архив.
3. Откройте PowerShell в распакованной папке.
4. Выполните команды:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

Навыки будут скопированы в пользовательскую папку:

```text
%USERPROFILE%\.agents\skills\
```

Если Codex уже был открыт, перезапустите его.

### Обновление библиотеки

Скачайте свежую версию репозитория, распакуйте архив, откройте PowerShell в новой папке и выполните:

```powershell
.\install.ps1 -Force
```

Без параметра `-Force` установщик пропускает уже существующие папки навыков. С параметром `-Force` файлы текущей версии библиотеки заменяются версиями из репозитория. Установщик ведёт манифест управляемых файлов и их SHA256-хешей `.personal-ai-library-manifest.json`. Устаревший файл удаляется только если его содержимое совпадает с последней установленной версией; изменённые вручную устаревшие и незарегистрированные пользовательские файлы сохраняются. Если манифеста нет, неизвестные файлы автоматически не удаляются.

### Безопасность установщика

`install.ps1` копирует файлы навыков в указанную папку. Он не устанавливает Python-пакеты, не подключается к API, не запускает скрипты навыков и не требует токенов или паролей.

Перед запуском можно просмотреть установщик и файлы навыков. Как и при использовании любого загруженного кода или инструкций, перед применением в рабочей среде следует проверить скрипты и внешние зависимости.

### Проверка и тесты

Для проверки структуры библиотеки и запуска Python-тестов нужен Python 3.9 или новее. Совместимость в CI проверяется на Python 3.9, 3.12 и 3.14. Для базовой проверки дополнительные пакеты не требуются:

```powershell
python .\validate_skills.py
```

Запуск Python-тестов:

```powershell
python -m unittest discover -s tests -v
```

Проверка установщика в PowerShell:

```powershell
.\tests\test_install.ps1
```

Повторяемая методика ручной оценки пяти пилотных Skills описана в [tests/SKILL-EVALUATION.md](tests/SKILL-EVALUATION.md).

GitHub Actions автоматически выполняет проверки при push и pull request. Workflow проверяет структуру навыков и установщик в Windows PowerShell 5.1 и PowerShell 7.

Проверки охватывают структуру репозитория, локальные ссылки, синтаксис проверяемых Python-файлов и работу установщика в тестовых сценариях. Они **не гарантируют**, что каждая методика подойдёт для любого проекта, что внешние сервисы будут доступны или что ИИ-агент всегда выдаст правильный результат.

### Принципы проекта

- **Практичность:** навыки должны решать реальные самостоятельные задачи.
- **Точность:** отделять подтверждённые факты от предположений и непроверенной информации.
- **Последовательность:** сначала исследование, затем план, после этого изменения.
- **Безопасность:** не раскрывать секреты и не выполнять необратимые действия без разрешения.
- **Контроль расходов:** не использовать платные API и сервисы без согласования.
- **Проверка источников:** проверять происхождение, лицензию, зависимости, скрипты и совместимость сторонних материалов.
- **Прозрачность:** указывать источники и ограничения; не заявлять о проверках, которые фактически не проводились.

Общие правила для агента находятся в [AGENTS.md](AGENTS.md). Источники и критерии отбора материалов описаны в [SOURCES.md](SOURCES.md). История изменений репозитория ведётся в [CHANGELOG.md](CHANGELOG.md).

### Структура репозитория

```text
Personal-AI-Library/
├── AGENTS.md
├── CATALOG.md
├── CATALOG-EN.md
├── CHANGELOG.md
├── SOURCES.md
├── README.md
├── LICENSE
├── LICENSE-CODE
├── LICENSE-CONTENT
├── install.ps1
├── validate_skills.py
├── skills/
│   └── <skill-name>/
│       ├── SKILL.md
│       ├── references/
│       └── scripts/
├── tests/
└── .github/workflows/
```

### Обратная связь и предложения

Если вы нашли ошибку, устаревшую инструкцию или хотите предложить новый навык, создайте [Issue на GitHub](https://github.com/HOADF/Personal-AI-Library/issues). По возможности укажите задачу, ожидаемое поведение и источники.

Новый навык должен решать отдельную практическую задачу, не дублировать существующие навыки и учитывать лицензии сторонних материалов.

### Лицензия

В репозитории используются **раздельные условия для программного кода и текстовых материалов**:

- **Установщик, валидатор, тесты, workflow и обозначенные вспомогательные скрипты:** [MIT License](LICENSE-CODE).
- **Навыки, инструкции, runbooks, чек-листы, шаблоны и документация:** [CC BY-NC-SA 4.0](LICENSE-CONTENT).

Текстовые материалы можно копировать и адаптировать для некоммерческих целей с указанием авторства. Распространяемые изменённые материалы должны иметь ту же или совместимую лицензию. Коммерческое использование этих текстовых материалов требует отдельного письменного разрешения правообладателя.

Точные границы и условия указаны в файлах лицензий. Сторонние материалы, если они присутствуют в репозитории, сохраняют собственные условия лицензирования.

---

**Repository:** https://github.com/HOADF/Personal-AI-Library  
**Maintainer / Автор проекта:** HOADF
