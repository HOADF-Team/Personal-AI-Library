# Источники и проверка сторонних материалов

Дата проверки: 26 ноября 2026.

## Официальная спецификация и документация

- OpenAI — Build skills: https://learn.chatgpt.com/docs/build-skills
- OpenAI Developers — Skills (Responses API): https://developers.openai.com/api/docs/guides/tools-skills
- OpenAI Developers — Build skills: https://developers.openai.com/plugins/build/skills
- OpenAI Developers — Testing Agent Skills Systematically with Evals: https://developers.openai.com/blog/eval-skills
- OpenAI — Skills in Plugins: https://developers.openai.com/plugins/concepts/skills
- OpenAI — Codex skill discovery и progressive disclosure описаны в официальной документации OpenAI.

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

- Лицензия в исходном репозитории: MIT.
- Проверены README, лицензия, `crypto-regime-analyzer`, `position-sizer` и `pre-trade-discipline-gate`.
- Crypto regime analyzer зависит от собственных Python-скриптов, методологии и файлов в `references/`; один SKILL.md не является рабочим комплектом.
- Position sizer ориентирован на акции, а не на perpetual futures.
- Эти файлы не переносились. Вместо этого добавлены самостоятельные инструкции по крипторынку, риску фьючерсов и аудиту торгового бота. Числовые оценки без исходных данных и воспроизводимой формулы запрещены.

### openai/skills
https://github.com/openai/skills

- Репозиторий помечен владельцем как deprecated.
- Не используется как актуальный источник для сборки.

## Принцип лицензирования

Библиотека не копирует сторонние каталоги целиком. В ней размещаются собственные инструкции, а источники указываются для прозрачности и дальнейшей проверки. Если в будущем будет перенесён сторонний файл или его существенная часть, рядом должны быть сохранены исходный URL, автор, лицензия и требуемые уведомления.
