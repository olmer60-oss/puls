# Пульс — локальная копия

Копия оверлея без сертификатов, LDAP-пароля, SMTP и корпоративных учёток.
Рабочий стенд в корне репозитория не трогается. Этот стек на порту **8081**.

```bash
cd 2.0/new
mkdir -p data/assets data/pg
MSYS_NO_PATHCONV=1 docker compose up -d db cache
MSYS_NO_PATHCONV=1 docker compose run --rm --no-deps seeder
MSYS_NO_PATHCONV=1 docker compose up -d
MSYS_NO_PATHCONV=1 docker compose exec web bundle exec rails runner /app/custom/seed_covenant_model.rb
```

UI: http://localhost:8081 `admin` / `admin`.

`.env` уже лежит рядом, секреты сгенерированы локально. LDAP и почта выключены.
