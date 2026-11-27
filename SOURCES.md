# Источники и проверка сторонних материалов

Дата проверки: 27 ноября 2026.

## Официальная спецификация и документация

- OpenAI — Build skills (Codex skill format, discovery, progressive disclosure and installation scopes): https://developers.openai.com/codex/skills
- OpenAI Developers — Skills (Responses API): https://developers.openai.com/api/docs/guides/tools-skills
- OpenAI Developers — Build skills: https://developers.openai.com/plugins/build/skills
- OpenAI Developers — Testing Agent Skills Systematically with Evals: https://developers.openai.com/blog/eval-skills
- OpenAI Developers — Skills in Plugins: https://developers.openai.com/plugins/concepts/skills
- OpenAI API Reference — Skills API endpoints (create, retrieve, update, delete and list): https://developers.openai.com/api/reference/cli

Навык — это папка с `SKILL.md`, где обязательны поля `name` и `description`. Дополнительные скрипты, ссылки и ресурсы подключаются только при необходимости. Описание навыка влияет на автоматический выбор, поэтому навыки должны быть узкими и не дублировать друг друга.

## Проверенные сторонние репозитории

### coreyhaines31/marketingskills
https://github.com/coreyhaines31/marketingskills

- Лицензия в исходном репозитории: MIT.
- Проверены README, лицензия и отдельные файлы `SKILL.md` для SEO, social, copywriting, product marketing и image.
- В исходных навыках есть ссылки на соседние навыки и дополнительные файлы `references/`. Простое копирование отдельных SKILL.md привело бы к отсутствующим зависимостям.
- Поэтому в библиотеку добавлены самостоятельные компактные инструкции по позиционированию, SEO и маркетинговым текстам. Исходные файлы и скрипты не копировались.

### JayLunia/trading-agent-skills
https://github.com/JayLunia/trading-agent-skills

- Это независимый fork проекта [tradermonty/claude-trading-skills](https://github.com/tradermonty/claude-trading-skills); это прямо указано в README форка и подтверждается метаданными GitHub.
- README форка указывает, что он сохраняет upstream MIT license и attribution; GitHub metadata форка также указывает MIT License.
- Проверены README, лицензия, `crypto-regime-analyzer`, `position-sizer` и `pre-trade-discipline-gate`.
- Crypto regime analyzer зависит от собственных Python-скриптов, методологии и файлов в `references/`; один SKILL.md не является рабочим комплектом.
- Position sizer ориентирован на акции, а не на perpetual futures.
- Эти файлы не переносились. Вместо этого добавлены самостоятельные инструкции по крипторынку, риску фьючерсов и аудиту торгового бота. Числовые оценки без исходных данных и воспроизводимой формулы запрещены.

### openai/skills
https://github.com/openai/skills

- В README исходного репозитория есть явное уведомление владельца: репозиторий deprecated; для актуальных примеров предлагается OpenAI Plugins repository и документация Codex.
- Не используется как актуальный источник для сборки.

## Принцип лицензирования

Библиотека не копирует сторонние каталоги целиком. В ней размещаются собственные инструкции, а источники указываются для прозрачности и дальнейшей проверки. Если в будущем будет перенесён сторонний файл или его существенная часть, рядом должны быть сохранены исходный URL, автор, лицензия и требуемые уведомления.


## Источники для server-security

- Ubuntu Server — Security suggestions: https://ubuntu.com/server/docs/explanation/security/security_suggestions/
- Ubuntu Server — Security architecture: https://ubuntu.com/server/docs/reference/security-architecture/
- Ubuntu Server — Defense in depth: https://ubuntu.com/server/docs/reference/security-architecture/defense-in-depth-layers/
- NIST SP 800-123 — Guide to General Server Security: https://csrc.nist.gov/pubs/sp/800/123/final
- CISA — Product Security Bad Practices: https://www.cisa.gov/resources-tools/resources/product-security-bad-practices
- OWASP — Secrets Management Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
- OWASP — Transport Layer Security Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Security_Cheat_Sheet.html

Использованы как ориентиры для собственной инструкции; тексты и сторонние навыки не копировались. Перед практическими изменениями сверяй рекомендации с версией ОС, провайдера и применяемой криптографической библиотеки.
