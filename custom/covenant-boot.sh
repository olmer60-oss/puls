#!/bin/bash
# Copy Covenant overlays into the container filesystem.
# Bind-mounts of .rb into /app on Docker Desktop (Windows) break Ruby's parser (stale mmap).
set -euo pipefail

SRC="${COVENANT_CUSTOM_DIR:-/covenant-custom}"

if [[ ! -d "$SRC" ]]; then
  echo "[covenant-boot] missing $SRC" >&2
  exit 1
fi

install -m 0644 "$SRC/zzz_covenant_ui.rb" /app/config/initializers/zzz_covenant_ui.rb
install -m 0644 "$SRC/zzz_covenant.ru.yml" /app/config/locales/zzz_covenant.ru.yml
install -m 0644 "$SRC/covenant-hide-ee.css" /app/public/covenant-hide-ee.css
mkdir -p /app/custom
install -m 0644 "$SRC/seed_covenant_model.rb" /app/custom/seed_covenant_model.rb
# совместимость со старыми командами на проде
ln -sfn /app/custom/seed_covenant_model.rb /app/custom/seed_orbita_model.rb
install -m 0644 "$SRC/covenant_ad.rb" /app/custom/covenant_ad.rb
if [[ -f "$SRC/seed_covenant_admins.rb" ]]; then
  install -m 0644 "$SRC/seed_covenant_admins.rb" /app/custom/seed_covenant_admins.rb
fi
if [[ -f "$SRC/zzz_covenant_ldap.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_ldap.rb" /app/config/initializers/zzz_covenant_ldap.rb
fi
if [[ -f "$SRC/zzz_covenant_mail.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_mail.rb" /app/config/initializers/zzz_covenant_mail.rb
fi
if [[ -f "$SRC/zzz_covenant_audit.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_audit.rb" /app/config/initializers/zzz_covenant_audit.rb
fi
if [[ -f "$SRC/zzz_covenant_due_mail.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_due_mail.rb" /app/config/initializers/zzz_covenant_due_mail.rb
fi
if [[ -f "$SRC/zzz_covenant_assignees.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_assignees.rb" /app/config/initializers/zzz_covenant_assignees.rb
fi
if [[ -f "$SRC/zzz_covenant_query_prefs.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_query_prefs.rb" /app/config/initializers/zzz_covenant_query_prefs.rb
fi
if [[ -f "$SRC/zzz_covenant_folders.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_folders.rb" /app/config/initializers/zzz_covenant_folders.rb
fi
if [[ -f "$SRC/covenant_folders_controller.rb" ]]; then
  install -m 0644 "$SRC/covenant_folders_controller.rb" \
    /app/app/controllers/covenant_folders_controller.rb
fi
if [[ -f "$SRC/zzz_covenant_ad_invite.rb" ]]; then
  install -m 0644 "$SRC/zzz_covenant_ad_invite.rb" \
    /app/config/initializers/zzz_covenant_ad_invite.rb
fi
if [[ -f "$SRC/covenant_ad_invite_controller.rb" ]]; then
  install -m 0644 "$SRC/covenant_ad_invite_controller.rb" \
    /app/app/controllers/covenant_ad_invite_controller.rb
fi
if [[ -f "$SRC/covenant-ad-invite.js" ]]; then
  install -m 0644 "$SRC/covenant-ad-invite.js" /app/public/covenant-ad-invite.js
fi

# Письма: назначение исполнителем / ответственным
mkdir -p /app/app/views/work_package_mailer
if [[ -f "$SRC/views/work_package_mailer/covenant_assignment.html.erb" ]]; then
  install -m 0644 "$SRC/views/work_package_mailer/covenant_assignment.html.erb" \
    /app/app/views/work_package_mailer/covenant_assignment.html.erb
fi
if [[ -f "$SRC/views/work_package_mailer/covenant_assignment.text.erb" ]]; then
  install -m 0644 "$SRC/views/work_package_mailer/covenant_assignment.text.erb" \
    /app/app/views/work_package_mailer/covenant_assignment.text.erb
fi
if [[ -f "$SRC/views/work_package_mailer/covenant_due.html.erb" ]]; then
  install -m 0644 "$SRC/views/work_package_mailer/covenant_due.html.erb" \
    /app/app/views/work_package_mailer/covenant_due.html.erb
fi
if [[ -f "$SRC/views/work_package_mailer/covenant_due.text.erb" ]]; then
  install -m 0644 "$SRC/views/work_package_mailer/covenant_due.text.erb" \
    /app/app/views/work_package_mailer/covenant_due.text.erb
fi

# View overlays (Windows bind-mount .erb в /app тоже лучше копировать)
mkdir -p /app/app/views/my
if [[ -f "$SRC/views/my/interface.html.erb" ]]; then
  install -m 0644 "$SRC/views/my/interface.html.erb" /app/app/views/my/interface.html.erb
fi

# Папки завода
mkdir -p /app/app/views/covenant_folders
if [[ -f "$SRC/views/covenant_folders/index.html.erb" ]]; then
  install -m 0644 "$SRC/views/covenant_folders/index.html.erb" \
    /app/app/views/covenant_folders/index.html.erb
fi

# Project create: один экран, «Завод AD» с родителя (ViewComponent + view)
mkdir -p /app/app/components/projects /app/app/views/projects
if [[ -f "$SRC/views/projects/new_component.html.erb" ]]; then
  install -m 0644 "$SRC/views/projects/new_component.html.erb" \
    /app/app/components/projects/new_component.html.erb
fi
if [[ -f "$SRC/views/projects/new.html.erb" ]]; then
  install -m 0644 "$SRC/views/projects/new.html.erb" \
    /app/app/views/projects/new.html.erb
fi

# /my/notifications: без project-specific блока
mkdir -p /app/app/components/my/notifications
if [[ -f "$SRC/views/my/notifications/show_page_component.html.erb" ]]; then
  install -m 0644 "$SRC/views/my/notifications/show_page_component.html.erb" \
    /app/app/components/my/notifications/show_page_component.html.erb
fi

# /my/notifications?tab=reminders: без wiki/news/forum/membership alerts
mkdir -p /app/app/components/my/reminders
if [[ -f "$SRC/views/my/reminders/show_page_component.html.erb" ]]; then
  install -m 0644 "$SRC/views/my/reminders/show_page_component.html.erb" \
    /app/app/components/my/reminders/show_page_component.html.erb
fi

# Brand: Пульс / ПМХ logo (+ favicon)
mkdir -p /app/custom/images
for f in pulse-logo.svg pulse-logo.png pulse-favicon.png pulse-favicon.ico; do
  if [[ -f "$SRC/images/$f" ]]; then
    install -m 0644 "$SRC/images/$f" "/app/public/$f"
    install -m 0644 "$SRC/images/$f" "/app/custom/images/$f"
  fi
done

# Normalize CRLF from Windows checkouts
sed -i 's/\r$//' \
  /app/config/initializers/zzz_covenant_ui.rb \
  /app/config/initializers/zzz_covenant_ldap.rb \
  /app/config/initializers/zzz_covenant_mail.rb \
  /app/config/initializers/zzz_covenant_audit.rb \
  /app/config/initializers/zzz_covenant_due_mail.rb \
  /app/config/initializers/zzz_covenant_assignees.rb \
  /app/config/initializers/zzz_covenant_query_prefs.rb \
  /app/config/initializers/zzz_covenant_folders.rb \
  /app/config/initializers/zzz_covenant_ad_invite.rb \
  /app/app/controllers/covenant_folders_controller.rb \
  /app/app/controllers/covenant_ad_invite_controller.rb \
  /app/public/covenant-ad-invite.js \
  /app/custom/seed_covenant_model.rb \
  /app/custom/covenant_ad.rb \
  /app/app/components/projects/new_component.html.erb \
  /app/app/views/projects/new.html.erb \
  /app/app/views/covenant_folders/index.html.erb \
  2>/dev/null || true

# Drop old locale name if present
rm -f /app/config/locales/covenant.ru.yml

# Avatar API: letter SVG вместо 404 — патч ДО загрузки Grape
AVATAR_API=/app/modules/avatars/lib/api/v3/users/user_avatar_api.rb
if [[ -f "$AVATAR_API" ]] && ! grep -q 'covenant_letter_avatar_svg' "$AVATAR_API"; then
  ruby - "$AVATAR_API" <<'RUBY'
path = ARGV[0]
raw = File.read(path)
repl = <<~'PATCH'
                else
                  # Covenant: letter SVG вместо 404 (фронт всегда делает <img src=.../avatar>)
                  letter_source =
                    if @user.respond_to?(:firstname) && @user.firstname.present?
                      @user.firstname
                    else
                      @user.name.to_s
                    end
                  letter = letter_source.to_s.strip[0]&.upcase || "?"
                  hue = "#{@user.id}#{@user.name}".each_byte.sum * 37 % 360
                  svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><rect width="128" height="128" rx="64" fill="hsl(#{hue} 45% 55%)"/><text x="64" y="64" text-anchor="middle" dominant-baseline="central" font-family="system-ui,sans-serif" font-size="64" font-weight="600" fill="#fff">#{letter}</text></svg>)
                  content_type "image/svg+xml"
                  header "Cache-Control", "private, max-age=86400"
                  body svg
                  # covenant_letter_avatar_svg
                end
PATCH
patched = raw.sub(/else\s*\n\s*status 404\s*\n\s*end/, repl.rstrip)
if patched != raw
  File.write(path, patched)
  warn "[covenant-boot] UserAvatarAPI → letter SVG"
end
RUBY
fi

# Frontend: не фетчить /api/v3/users/:id/avatar
ruby - <<'RUBY'
Dir["/app/public/assets/frontend/chunk-*.js"].each do |path|
  raw = File.read(path)
  next unless raw.include?("userAvatarUrl(principal)") && raw.include?("renderUserAvatar")
  next if raw.include?("userAvatarUrl(principal){return null")

  patched = raw.sub(
    /userAvatarUrl\(principal\)\s*\{\s*const id =/,
    "userAvatarUrl(principal){return null;const id="
  )
  next if patched == raw

  File.write(path, patched)
  warn "[covenant-boot] patched avatar JS #{File.basename(path)}"
end
RUBY

echo "[covenant-boot] overlays installed (Пульс)"
exec "$@"
