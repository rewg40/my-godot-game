# my-godot-game

Исходники игры и сайт-документация ZOMBI.

- Сайт: https://rewg40.github.io/my-godot-game/
- Редактирование «ИИ монстров»: https://rewg40.github.io/my-godot-game/?edit=1#mechanics/zombies
- Полный редактор ассетов: https://rewg40.github.io/my-godot-game/?edit=1#mechanics/assets
- Исходники сайта: `game-docs/src/` на ветке `arena/d4678daa-my-godot-game`.
- Редактор вкладок, открытые вопросы, публикация и GitHub 401: [`game-docs/src/docs/USAGE.md`](game-docs/src/docs/USAGE.md).
- Проверки: `npm ci --prefix game-docs && npm test --prefix game-docs`.

Кнопка «Сохранить во вкладке» сохраняет правку в текущем браузере. «Опубликовать вкладку» отправляет её в GitHub и делает общей после обновления Pages; для этого нужен токен владельца. «Сохранить и отправить ИИ» создаёт задачу в `agent-inbox` на целостную обработку изменения; затем напишите агенту «разбери inbox». Токены нельзя добавлять в config.json, ссылки или файлы репозитория. Код доступа удалён: рабочая ссылка сразу открывает редактор. Публичный сайт не является средством защиты секретных данных.
