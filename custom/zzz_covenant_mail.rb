# frozen_string_literal: true

# Covenant: свои письма — исполнители (CF + assigned/responsible), due-mail в zzz_covenant_due_mail.rb.
# Сток OP (digest ~08:00, @mention, watcher/comment после aggregation) на почту не шлём.

module CovenantAssignmentMail
  module_function

  def ensure_smtp!
    return unless defined?(Setting) && Setting.respond_to?(:reload_mailer_settings!)

    addr = ActionMailer::Base.smtp_settings[:address].to_s
    return if addr.present? && addr != "localhost"

    Setting.reload_mailer_settings!
  rescue StandardError
    nil
  end

  def deliver!(notification)
    return false unless notification.reason_assigned? || notification.reason_responsible?
    return false if notification.journal.blank? || notification.recipient.blank?
    return false if notification.mail_alert_sent

    ensure_smtp!

    Rails.logger.info(
      "[covenant] sending assignment mail reason=#{notification.reason} " \
      "to=#{notification.recipient_id}/#{notification.recipient.mail} wp=#{notification.resource_id}"
    )

    WorkPackageMailer
      .covenant_assignment(notification.recipient, notification.journal, notification.reason)
      .deliver_now

    notification.update_columns(mail_alert_sent: true, updated_at: Time.current)
    Rails.logger.info("[covenant] SENT assignment mail n=#{notification.id}")
    true
  rescue StandardError => e
    Rails.logger.error("[covenant] assignment mail FAILED n=#{notification.id}: #{e.class}: #{e.message}")
    false
  end

  def skip_stock_assigned?(notification)
    return false unless notification.reason_assigned?

    wp = notification.journal&.journable
    return false unless wp.is_a?(WorkPackage) && defined?(CovenantAssignees)

    cf = CovenantAssignees.custom_field
    cf && wp.type&.custom_field_ids&.include?(cf.id)
  end

  def deliver_user!(user, work_package, reason: "assigned")
    return false if user.blank? || work_package.blank?
    return false unless user.mail.to_s.include?("@")

    journal = work_package.journals.reorder(:version).last
    return false if journal.blank?

    ensure_smtp!

    Rails.logger.info(
      "[covenant] sending assignment mail reason=#{reason} " \
      "to=#{user.id}/#{user.mail} wp=#{work_package.id} (cf executors)"
    )

    WorkPackageMailer
      .covenant_assignment(user, journal, reason)
      .deliver_now
    Rails.logger.info("[covenant] SENT assignment mail user=#{user.login} wp=#{work_package.id}")
    true
  rescue StandardError => e
    Rails.logger.warn("[covenant] assignment mail SMTP skip user=#{user.try(:login)}: #{e.class}: #{e.message}")
    false
  end
end

def covenant_patch_assignment_mailer!
  return unless defined?(WorkPackageMailer)

  WorkPackageMailer.class_eval do
    def covenant_assignment(recipient, journal, reason)
      @user = recipient
      @work_package = journal.journable
      @journal = journal
      @reason = reason.to_s
      @unique_reasons = [@reason.to_sym]

      author = journal.user

      User.execute_as(author) do
        set_work_package_headers(@work_package)

        message_id journal, recipient
        references journal

        key = @reason == "responsible" ? "covenant.mail.assignment.subject_responsible" : "covenant.mail.assignment.subject_assigned"

        send_localized_mail(recipient) do
          I18n.t(key,
                 user_name: author.name,
                 id: @work_package.formatted_id,
                 subject: @work_package.subject)
        end
      end
    end
  end

  Rails.logger.info("[covenant] WorkPackageMailer#covenant_assignment")
rescue StandardError => e
  Rails.logger.warn("[covenant] assignment mailer patch failed: #{e.class}: #{e.message}")
end

def covenant_patch_wp_mail_strategy!
  strategy = begin
    Notifications::MailService::WorkPackageStrategy
  rescue NameError
    nil
  end
  return unless strategy

  strategy.singleton_class.class_eval do
    unless method_defined?(:covenant_original_send_mail)
      alias_method :covenant_original_send_mail, :send_mail
    end

    def send_mail(notification)
      if notification.reason_assigned? || notification.reason_responsible?
        return true if CovenantAssignmentMail.skip_stock_assigned?(notification)

        return true if CovenantAssignmentMail.deliver!(notification)

        return nil
      end

      Rails.logger.info("[covenant] skip WP strategy mail reason=#{notification.reason}")
      true
    end
  end

  Rails.logger.info("[covenant] MailService: covenant assignment mail only (no stock WP mail)")
rescue StandardError => e
  Rails.logger.warn("[covenant] WP mail strategy patch failed: #{e.class}: #{e.message}")
end

def covenant_patch_stock_notification_mail_service!
  return unless defined?(Notifications::MailService)

  Notifications::MailService.class_eval do
    unless method_defined?(:covenant_original_mail_service_call)
      alias_method :covenant_original_mail_service_call, :call
    end

    def call
      if notification.reason_assigned? || notification.reason_responsible?
        return covenant_original_mail_service_call
      end

      with_marked_notifications(notification.id) do
        Rails.logger.info(
          "[covenant] skip stock notification mail reason=#{notification.reason} n=#{notification.id}"
        )
        true
      end
    end
  end

  Rails.logger.info("[covenant] MailService: non-assigned/responsible notification mail disabled")
rescue StandardError => e
  Rails.logger.warn("[covenant] MailService skip patch failed: #{e.class}: #{e.message}")
end

def covenant_patch_reminder_digest_jobs!
  if defined?(Notifications::ScheduleReminderMailsJob)
    Notifications::ScheduleReminderMailsJob.class_eval do
      def perform
        Rails.logger.info("[covenant] ScheduleReminderMailsJob skipped (OP digest disabled)")
      end
    end
  end

  if defined?(Mails::ReminderJob)
    Mails::ReminderJob.class_eval do
      def perform(*)
        Rails.logger.info("[covenant] Mails::ReminderJob skipped (OP digest disabled)")
      end
    end
  end

  Rails.logger.info("[covenant] OP daily digest / reminder mail jobs disabled")
rescue StandardError => e
  Rails.logger.warn("[covenant] digest job patch failed: #{e.class}: #{e.message}")
end

def covenant_patch_notification_workflow!
  return unless defined?(Notifications::WorkflowJob)

  Notifications::WorkflowJob.state :create_notifications,
                                   to: :send_mails do |resource, send_notification|
    immediate, delayed = Notifications::CreateFromModelService
                         .new(resource)
                         .call(send_notification)
                         .all_results
                         .partition do |n|
      n.reason_mentioned? || n.reason_assigned? || n.reason_responsible?
    end

    Rails.logger.info(
      "[covenant] WorkflowJob notifications immediate=#{immediate.size} delayed=#{delayed.size} " \
      "reasons=#{(immediate + delayed).map(&:reason).uniq.join(',')} " \
      "mail_alert=#{immediate.map { |n| [n.id, n.mail_alert_sent.inspect].join(':') }.join('|')}"
    )

    immediate.each do |notification|
      # nil и false — оба «ещё не отправлено» (сток сравнивал только с false → пропускал nil)
      next if notification.mail_alert_sent

      next unless notification.reason_assigned? || notification.reason_responsible?

      unless CovenantAssignmentMail.skip_stock_assigned?(notification)
        CovenantAssignmentMail.deliver!(notification)
      end
    end

    delayed.map(&:id)
  end

  Notifications::WorkflowJob.state :send_mails,
                                   wait: -> { Setting.journal_aggregation_time_minutes.to_i.minutes } do |*notification_ids|
    Rails.logger.info(
      "[covenant] WorkflowJob send_mails skipped (stock OP mail disabled) count=#{notification_ids&.compact&.size || 0}"
    )
  end

  Rails.logger.info("[covenant] WorkflowJob: covenant assignment mail only; send_mails noop")
rescue StandardError => e
  Rails.logger.warn("[covenant] WorkflowJob patch failed: #{e.class}: #{e.message}")
end

Rails.application.config.to_prepare do
  covenant_patch_assignment_mailer!
  covenant_patch_wp_mail_strategy!
  covenant_patch_stock_notification_mail_service!
  covenant_patch_reminder_digest_jobs!
  covenant_patch_notification_workflow!
end

Rails.application.config.after_initialize do
  covenant_patch_assignment_mailer!
  covenant_patch_wp_mail_strategy!
  covenant_patch_stock_notification_mail_service!
  covenant_patch_reminder_digest_jobs!
  covenant_patch_notification_workflow!
end
