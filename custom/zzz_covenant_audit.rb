# frozen_string_literal: true

# Covenant: audit log for deleted work packages (ковенанты) and attachments.
# Append-only table covenant_deletion_logs — survives record deletion.
# Record class MUST be defined after ApplicationRecord is loaded (not at initializer parse).

module CovenantDeletionLog
  class << self
    def record_class
      unless const_defined?(:Record, false)
        const_set(:Record, Class.new(ApplicationRecord) do
          self.table_name = "covenant_deletion_logs"
        end)
      end
      const_get(:Record, false)
    end

    def ensure_table
      return true if @table_ready

      conn = ActiveRecord::Base.connection
      unless conn.table_exists?(:covenant_deletion_logs)
        conn.create_table :covenant_deletion_logs do |t|
          t.string :record_type, null: false, limit: 32
          t.bigint :record_id, null: false
          t.bigint :project_id
          t.string :subject
          t.bigint :user_id
          t.string :user_login
          t.string :user_mail
          t.datetime :deleted_at, null: false
          t.jsonb :snapshot, default: {}
        end
        conn.add_index :covenant_deletion_logs, %i[record_type record_id], name: "index_covenant_deletion_logs_on_type_and_record"
        conn.add_index :covenant_deletion_logs, :deleted_at
        conn.add_index :covenant_deletion_logs, :user_login
      end

      record_class
      @table_ready = true
      true
    rescue StandardError => e
      Rails.logger.error("[covenant-audit] ensure_table failed: #{e.class}: #{e.message}")
      false
    end

    def current_user_attrs
      user = User.current if defined?(User) && User.respond_to?(:current)
      {
        user_id: user&.id,
        user_login: user&.login.to_s.presence || "system",
        user_mail: user&.mail.to_s
      }
    end

    def log_work_package(work_package)
      return unless ensure_table

      attrs = current_user_attrs
      record_class.create!(
        record_type: "work_package",
        record_id: work_package.id,
        project_id: work_package.project_id,
        subject: work_package.subject.to_s.truncate(500),
        deleted_at: Time.current,
        snapshot: work_package_snapshot(work_package),
        **attrs
      )
      Rails.logger.info(
        "[covenant-audit] work_package deleted id=#{work_package.id} " \
        "by=#{attrs[:user_login]} project=#{work_package.project&.identifier}"
      )
    rescue StandardError => e
      Rails.logger.error("[covenant-audit] log work_package #{work_package.id} failed: #{e.class}: #{e.message}")
    end

    def log_attachment(attachment)
      return unless ensure_table

      project_id = attachment_project_id(attachment)
      attrs = current_user_attrs
      record_class.create!(
        record_type: "attachment",
        record_id: attachment.id,
        project_id: project_id,
        subject: attachment.filename.to_s.truncate(500),
        deleted_at: Time.current,
        snapshot: attachment_snapshot(attachment),
        **attrs
      )
      Rails.logger.info(
        "[covenant-audit] attachment deleted id=#{attachment.id} " \
        "file=#{attachment.filename} by=#{attrs[:user_login]}"
      )
    rescue StandardError => e
      Rails.logger.error("[covenant-audit] log attachment #{attachment.id} failed: #{e.class}: #{e.message}")
    end

    def attachment_project_id(attachment)
      container = attachment.container
      case container
      when WorkPackage
        container.project_id
      when Project
        container.id
      end
    end

    def work_package_snapshot(work_package)
      {
        formatted_id: work_package.respond_to?(:formatted_id) ? work_package.formatted_id : "##{work_package.id}",
        type: work_package.type&.name,
        status: work_package.status&.name,
        priority: work_package.priority&.name,
        author_login: work_package.author&.login,
        assignee_login: work_package.assigned_to&.login,
        project_identifier: work_package.project&.identifier,
        project_name: work_package.project&.name,
        due_date: work_package.due_date&.iso8601,
        created_at: work_package.created_at&.iso8601,
        updated_at: work_package.updated_at&.iso8601
      }
    end

    def attachment_snapshot(attachment)
      container = attachment.container
      data = {
        filename: attachment.filename,
        filesize: attachment.filesize,
        content_type: attachment.content_type,
        description: attachment.description,
        container_type: attachment.container_type,
        container_id: attachment.container_id
      }
      if container.is_a?(WorkPackage)
        data[:work_package_id] = container.id
        data[:work_package_subject] = container.subject
        data[:project_identifier] = container.project&.identifier
      end
      data
    end
  end
end

def covenant_patch_deletion_audit!
  ready = CovenantDeletionLog.ensure_table
  unless ready
    Rails.logger.warn("[covenant-audit] table not ready, hooks skipped")
    return
  end

  unless defined?(CovenantWpDeletionAudit)
    Object.const_set(:CovenantWpDeletionAudit, Module.new do
      def covenant_audit_log_work_package_deletion
        CovenantDeletionLog.log_work_package(self)
      end
    end)
  end

  unless defined?(CovenantAttachmentDeletionAudit)
    Object.const_set(:CovenantAttachmentDeletionAudit, Module.new do
      def covenant_audit_log_attachment_deletion
        CovenantDeletionLog.log_attachment(self)
      end
    end)
  end

  if defined?(WorkPackage) && !WorkPackage.included_modules.include?(CovenantWpDeletionAudit)
    WorkPackage.include(CovenantWpDeletionAudit)
    WorkPackage.before_destroy :covenant_audit_log_work_package_deletion
  end

  if defined?(Attachment) && !Attachment.included_modules.include?(CovenantAttachmentDeletionAudit)
    Attachment.include(CovenantAttachmentDeletionAudit)
    Attachment.before_destroy :covenant_audit_log_attachment_deletion
  end

  Rails.logger.info("[covenant-audit] deletion audit hooks active")
rescue StandardError => e
  Rails.logger.warn("[covenant-audit] patch failed: #{e.class}: #{e.message}")
end

Rails.application.config.to_prepare do
  covenant_patch_deletion_audit!
end

Rails.application.config.after_initialize do
  covenant_patch_deletion_audit!
end
