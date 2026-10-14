# frozen_string_literal: true

# Covenant: письма за 3 дня до due_date и в день, когда ковенанта стала просроченной.
# Сток OP date alerts — EE, у нас Community. Идемпотентно: covenant_due_mails.
# Вешаемся на ночной Cron::ClearOldSessionsJob (01:15 UTC) + свой Cron::CronJob если есть.

module CovenantDueMail
  KIND_SOON = "due_soon"
  KIND_OVERDUE = "overdue"

  class << self
    def soon_days
      (ENV["COVENANT_DUE_SOON_DAYS"].presence || 3).to_i
    end

    def min_hours_between_runs
      (ENV["COVENANT_DUE_MAIL_MIN_HOURS"].presence || 20).to_i.clamp(1, 168)
    end

    def cron_run_cache_key
      "covenant_due_mail_last_run"
    end

    def time_zone
      ENV["COVENANT_DUE_MAIL_TZ"].presence || "Asia/Krasnoyarsk"
    end

    def record_class
      unless const_defined?(:Record, false)
        const_set(:Record, Class.new(ApplicationRecord) do
          self.table_name = "covenant_due_mails"
        end)
      end
      const_get(:Record, false)
    end

    def ensure_table
      return true if @table_ready

      conn = ActiveRecord::Base.connection
      unless conn.table_exists?(:covenant_due_mails)
        conn.create_table :covenant_due_mails do |t|
          t.bigint :work_package_id, null: false
          t.string :kind, null: false, limit: 32
          t.date :due_date, null: false
          t.datetime :sent_at, null: false
        end
        conn.add_index :covenant_due_mails, %i[work_package_id kind due_date],
                       unique: true, name: "index_covenant_due_mails_unique"
      end

      record_class
      @table_ready = true
      true
    rescue StandardError => e
      Rails.logger.error("[covenant-due] ensure_table failed: #{e.class}: #{e.message}")
      false
    end

    def run(force: false)
      return false unless ensure_table
      return false unless defined?(WorkPackage)

      force ||= ENV["COVENANT_DUE_MAIL_FORCE"] == "1"
      unless force
        last = Rails.cache.read(cron_run_cache_key)
        if last.is_a?(Time) && last > min_hours_between_runs.hours.ago
          Rails.logger.info(
            "[covenant-due] run skipped (ran at #{last.utc.iso8601}, " \
            "min interval #{min_hours_between_runs}h; COVENANT_DUE_MAIL_FORCE=1 to override)"
          )
          return 0
        end
      end

      Rails.cache.write(cron_run_cache_key, Time.current, expires_in: 48.hours)

      today = today_date
      sent = 0

      flipped = 0
      Time.use_zone(time_zone) do
        sent += process_scope(KIND_SOON, open_packages.where(due_date: today + soon_days))
        sent += process_scope(KIND_OVERDUE, open_packages.where("due_date < ?", today))
        flipped = mark_overdue!
      end

      Rails.logger.info("[covenant-due] run today=#{today} soon_days=#{soon_days} sent=#{sent} overdue_status=#{flipped}")
      sent
    rescue StandardError => e
      Rails.logger.error("[covenant-due] run failed: #{e.class}: #{e.message}")
      0
    end

    def today_date
      Time.find_zone(time_zone)&.today || Date.current
    end

    def requested_status
      Status.find_by(name: "Запрошен") if defined?(Status)
    end

    def overdue_status
      Status.find_by(name: "Просрочено") if defined?(Status)
    end

    def overdue?(wp)
      return false unless wp&.due_date
      return false unless wp.status&.name == "Запрошен"

      wp.due_date < today_date
    end

    def apply_status!(wp)
      return false unless overdue?(wp)

      overdue = overdue_status
      return false unless overdue
      return false if wp.status_id == overdue.id

      wp.status = overdue
      true
    end

    def mark_overdue!
      requested = requested_status
      overdue = overdue_status
      return 0 unless requested && overdue

      n = 0
      WorkPackage.where(status_id: requested.id).where("due_date < ?", today_date).find_each do |wp|
        n += 1 if flip_to_overdue!(wp, overdue)
      end
      n
    end

    def flip_to_overdue!(wp, overdue = overdue_status)
      return false unless wp && overdue
      return false unless overdue?(wp)

      wp.instance_variable_set(:@covenant_overdue_status_flip, true)
      wp.status = overdue
      wp.save(validate: false)
      Rails.logger.info("[covenant-due] status Просрочено wp=#{wp.id} due=#{wp.due_date}")
      true
    rescue StandardError => e
      Rails.logger.warn("[covenant-due] overdue status wp=#{wp.id}: #{e.class}: #{e.message}")
      false
    end

    def open_packages
      rel = WorkPackage.where.not(due_date: nil)
      if defined?(Status) && WorkPackage.reflect_on_association(:status)
        rel = rel.joins(:status).where(statuses: { is_closed: false })
      end
      rel
    end

    def process_scope(kind, scope)
      n = 0
      scope.find_each do |wp|
        n += 1 if deliver_for(wp, kind)
      end
      n
    end

    def already_sent?(wp, kind)
      record_class.exists?(work_package_id: wp.id, kind: kind, due_date: wp.due_date)
    end

    def claim!(wp, kind)
      record_class.create!(
        work_package_id: wp.id,
        kind: kind,
        due_date: wp.due_date,
        sent_at: Time.current
      )
      true
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      false
    end

    def unclaim!(wp, kind)
      record_class.where(work_package_id: wp.id, kind: kind, due_date: wp.due_date).delete_all
    end

    def recipients_for(wp, kind)
      users = if defined?(CovenantAssignees)
                CovenantAssignees.users_for(wp)
              else
                [wp.assigned_to].compact
              end
      users << wp.author if kind == KIND_OVERDUE && wp.author.is_a?(User)

      users.compact.uniq.select do |user|
        user.is_a?(User) &&
          user.mail.to_s.include?("@") &&
          (!user.respond_to?(:active?) || user.active?)
      end
    end

    def deliver_for(wp, kind)
      return false if already_sent?(wp, kind)

      users = recipients_for(wp, kind)
      if users.empty?
        Rails.logger.info("[covenant-due] skip wp=#{wp.id} kind=#{kind} (no recipients)")
        return false
      end

      return false unless claim!(wp, kind)

      ensure_smtp
      delivered = 0
      users.each do |user|
        WorkPackageMailer.covenant_due(user, wp, kind).deliver_now
        delivered += 1
        Rails.logger.info(
          "[covenant-due] SENT kind=#{kind} wp=#{wp.id} due=#{wp.due_date} to=#{user.login}/#{user.mail}"
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[covenant-due] SMTP skip wp=#{wp.id} kind=#{kind} to=#{user.login}/#{user.mail}: #{e.class}: #{e.message}"
        )
      end

      if delivered.zero?
        Rails.logger.warn("[covenant-due] no SMTP success wp=#{wp.id} kind=#{kind} (will not retry)")
      end

      true
    rescue StandardError => e
      unclaim!(wp, kind)
      Rails.logger.error("[covenant-due] FAILED wp=#{wp.id} kind=#{kind}: #{e.class}: #{e.message}")
      false
    end

    def ensure_smtp
      if defined?(CovenantAssignmentMail)
        CovenantAssignmentMail.ensure_smtp!
        return
      end
      return unless defined?(Setting) && Setting.respond_to?(:reload_mailer_settings!)

      addr = ActionMailer::Base.smtp_settings[:address].to_s
      Setting.reload_mailer_settings! if addr.blank? || addr == "localhost"
    rescue StandardError
      nil
    end
  end
end

def covenant_patch_due_mailer!
  return unless defined?(WorkPackageMailer)

  WorkPackageMailer.class_eval do
    def covenant_due(recipient, work_package, kind)
      @user = recipient
      @work_package = work_package
      @kind = kind.to_s
      @unique_reasons = [@kind == CovenantDueMail::KIND_OVERDUE ? :overdue : :due_date]

      User.execute_as(recipient) do
        set_work_package_headers(work_package) if respond_to?(:set_work_package_headers, true)

        key = @kind == CovenantDueMail::KIND_OVERDUE ? "covenant.mail.due.subject_overdue" : "covenant.mail.due.subject_soon"

        send_localized_mail(recipient) do
          I18n.t(key,
                 id: work_package.formatted_id,
                 subject: work_package.subject,
                 date: work_package.due_date,
                 days: CovenantDueMail.soon_days)
        end
      end
    end
  end

  Rails.logger.info("[covenant-due] WorkPackageMailer#covenant_due")
rescue StandardError => e
  Rails.logger.warn("[covenant-due] mailer patch failed: #{e.class}: #{e.message}")
end

def covenant_hook_due_mail_cron!
  CovenantDueMail.ensure_table

  if defined?(Cron::ClearOldSessionsJob) && !Cron::ClearOldSessionsJob.instance_variable_get(:@covenant_due_hooked)
    Cron::ClearOldSessionsJob.after_perform { CovenantDueMail.run }
    Cron::ClearOldSessionsJob.instance_variable_set(:@covenant_due_hooked, true)
    Rails.logger.info("[covenant-due] hooked Cron::ClearOldSessionsJob after_perform")
  end

  # Один триггер: after_perform на ClearOldSessionsJob (~01:15 UTC).
  # Отдельный CronJob не регистрируем — при recreate worker GoodJob мог догонять
  # два cron и гонять run подряд; плюс debounce в CovenantDueMail.run.

  Rails.logger.info("[covenant-due] cron hooks ready tz=#{CovenantDueMail.time_zone} soon_days=#{CovenantDueMail.soon_days}")
rescue StandardError => e
  Rails.logger.warn("[covenant-due] cron hook failed: #{e.class}: #{e.message}")
end

def covenant_patch_wp_overdue_status!
  return unless defined?(WorkPackage)

  unless defined?(CovenantWpOverdueStatus)
    Object.const_set(:CovenantWpOverdueStatus, Module.new do
      def covenant_apply_overdue_status
        CovenantDueMail.apply_status!(self) if defined?(CovenantDueMail)
      end
    end)
  end

  unless WorkPackage.included_modules.include?(CovenantWpOverdueStatus)
    WorkPackage.include(CovenantWpOverdueStatus)
    WorkPackage.before_save :covenant_apply_overdue_status
  end

  Rails.logger.info("[covenant-due] WP Запрошен + due_date < сегодня → Просрочено")
rescue StandardError => e
  Rails.logger.warn("[covenant-due] WP overdue status patch failed: #{e.class}: #{e.message}")
end

Rails.application.config.to_prepare do
  covenant_patch_due_mailer!
  covenant_hook_due_mail_cron!
  covenant_patch_wp_overdue_status!
end

Rails.application.config.after_initialize do
  covenant_patch_due_mailer!
  covenant_hook_due_mail_cron!
  covenant_patch_wp_overdue_status!
end
