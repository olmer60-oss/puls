# frozen_string_literal: true

# Covenant: несколько исполнителей на ковенанте.
# Сток OP assigned_to — один Principal. Держим CF «Исполнители» (user, multi)
# и синхронизируем первого в assigned_to (фильтры/API). Письма — всем из CF.

module CovenantAssignees
  CF_NAME = "Исполнители"

  class << self
    def custom_field
      return @custom_field if defined?(@custom_field) && @custom_field

      @custom_field = WorkPackageCustomField.find_by(name: CF_NAME) if defined?(WorkPackageCustomField)
    end

    def reset!
      @custom_field = nil
    end

    def user_ids_for(work_package)
      cf = custom_field
      return [] unless cf && work_package

      rows =
        if work_package.respond_to?(:custom_field_values)
          work_package.custom_field_values.select { |cv| cv.custom_field_id == cf.id }
        else
          work_package.custom_values.select { |cv| cv.custom_field_id == cf.id }
        end

      rows
        .reject { |cv| cv.respond_to?(:marked_for_destruction?) && cv.marked_for_destruction? }
        .select { |cv| cv.value.present? }
        .map { |cv| cv.value.to_i }
        .uniq
    end

    # Вызов custom_field_values= — единственный момент, когда пустой список ещё виден.
    # before_save сток уже подменяет association, и по changes очистку не отличить.
    def remember_executor_assignment!(work_package, values)
      return unless values.is_a?(Hash)

      cf = custom_field
      return unless cf

      key = values.keys.find { |k| k.to_s == cf.id.to_s }
      return unless key

      ids = Array(values[key]).filter_map { |v|
        raw = v.is_a?(Integer) || v.is_a?(String) || v.nil? ? v : (v.respond_to?(:id) ? v.id : v)
        n = raw.to_i
        n.zero? ? nil : n
      }.uniq
      work_package.instance_variable_set(:@covenant_executors_explicit, true)
      work_package.instance_variable_set(:@covenant_executors_ids, ids)
    end

    def cf_cleared?(work_package)
      cf = custom_field
      return false unless cf && work_package.respond_to?(:custom_field_changes)

      change = work_package.custom_field_changes[cf.attribute_name]
      return false unless change

      old_vals, new_vals = change
      Array(old_vals).any?(&:present?) && Array(new_vals).all?(&:blank?)
    end

    def users_for(work_package)
      ids = user_ids_for(work_package)
      ids |= [work_package.assigned_to_id] if work_package.assigned_to_id
      return [] if ids.empty? || !defined?(User)

      User.where(id: ids).to_a
    end

    def db_user_ids(work_package_id)
      cf = custom_field
      return [] unless cf

      CustomValue.where(
        customized_type: "WorkPackage",
        customized_id: work_package_id,
        custom_field_id: cf.id
      ).where.not(value: [nil, ""]).pluck(:value).map(&:to_i).uniq
    end

    def sql_contains_user_ids(user_ids)
      cf = custom_field
      ids = Array(user_ids).map(&:to_i).reject(&:zero?).uniq
      return nil if cf.nil? || ids.empty?

      list = ids.join(",")
      "work_packages.id IN (" \
        "SELECT custom_values.customized_id FROM custom_values " \
        "WHERE custom_values.custom_field_id = #{cf.id} " \
        "AND custom_values.customized_type = 'WorkPackage' " \
        "AND custom_values.value IN (#{list})" \
        ")"
    end

    def replace_custom_values!(work_package, user_ids)
      cf = custom_field
      return unless cf && work_package.persisted?

      ids = Array(user_ids).map(&:to_i).reject(&:zero?).uniq
      CustomValue.where(
        customized_type: "WorkPackage",
        customized_id: work_package.id,
        custom_field_id: cf.id
      ).delete_all
      ids.each do |uid|
        CustomValue.create!(
          customized: work_package,
          custom_field: cf,
          value: uid.to_s
        )
      end
      work_package.custom_values.reset if work_package.respond_to?(:custom_values)
    end

    def sync_assigned_to!(work_package, clear_when_empty: false)
      ids = user_ids_for(work_package)
      if ids.empty?
        return unless clear_when_empty
        return if work_package.assigned_to_id.nil?

        work_package.assigned_to_id = nil
        return
      end
      return if work_package.assigned_to_id == ids.first

      work_package.assigned_to_id = ids.first
    end

    def ensure_cf_from_assigned_to!(work_package)
      return unless work_package.assigned_to_id
      return if user_ids_for(work_package).any?

      replace_custom_values!(work_package, [work_package.assigned_to_id])
      work_package.custom_values.reload if work_package.respond_to?(:custom_values)
    end

    def mail_added!(work_package, previous_ids, **_opts)
      was = Array(previous_ids).map(&:to_i).uniq
      now = user_ids_for(work_package)
      return if was.sort == now.sort

      added = now - was

      added.each do |uid|
        user = User.find_by(id: uid)
        next unless user

        CovenantAssignmentMail.deliver_user!(user, work_package, reason: "assigned")
      end
    end

    # Пусто = нет CF «Исполнители». assigned_to не смотрим: OP часто пишет туда
    # автора/текущего юзера, в UI «—», каскад иначе пропускает «это он и есть».
    def empty_executors?(work_package)
      return true unless work_package

      db_user_ids(work_package.id).empty?
    end

    def executor_ids(work_package)
      ids = user_ids_for(work_package)
      ids |= [work_package.assigned_to_id] if work_package&.assigned_to_id
      ids
    end

    def cascade_to_empty_children!(parent)
      return unless parent&.persisted?

      ids = executor_ids(parent)
      return if ids.empty?

      seen = Thread.current[:covenant_cascade_ids] ||= []
      return if seen.include?(parent.id)

      seen << parent.id
      pushed = true
      WorkPackage.where(parent_id: parent.id).find_each do |child|
        next unless empty_executors?(child)

        apply_executors!(child, ids)
        Rails.logger.info("[covenant-assignees] cascade parent=#{parent.id} → child=#{child.id} users=#{ids.join(",")}")
      end
    ensure
      if pushed
        seen.delete(parent.id)
        Thread.current[:covenant_cascade_ids] = nil if seen.empty?
      end
    end

    def apply_executors!(work_package, user_ids)
      cf = custom_field
      return unless cf && work_package

      ids = Array(user_ids).map(&:to_i).reject(&:zero?).uniq
      return if ids.empty?

      actor = (defined?(User) && User.current) || nil
      if defined?(WorkPackages::UpdateService) && actor&.logged?
        call = WorkPackages::UpdateService
               .new(user: actor, model: work_package)
               .call(custom_field_values: { cf.id => ids.map(&:to_s) })
        return if call.success?

        Rails.logger.warn("[covenant-assignees] cascade UpdateService child=#{work_package.id}: #{call.message}")
      end

      replace_custom_values!(work_package, ids)
      work_package.reload
      sync_assigned_to!(work_package)
      work_package.save(validate: false)
    end
  end
end

def covenant_patch_assignee_filters!
  unless defined?(CovenantAssigneeFilterOrCf)
    Object.const_set(:CovenantAssigneeFilterOrCf, Module.new do
      def where
        base = super
        ids = Array(values).map { |v| v.to_s == "me" ? User.current&.id : v.to_i }
        extra = CovenantAssignees.sql_contains_user_ids(ids)
        return base if extra.blank?

        case operator.to_s
        when "!"
          "(#{base}) AND NOT (#{extra})"
        else
          "(#{base}) OR (#{extra})"
        end
      end
    end)
  end

  %w[
    Queries::WorkPackages::Filter::AssigneeOrGroupFilter
    Queries::WorkPackages::Filter::AssignedToFilter
  ].each do |name|
    klass = name.safe_constantize
    next unless klass
    next if klass.ancestors.include?(CovenantAssigneeFilterOrCf)

    klass.prepend(CovenantAssigneeFilterOrCf)
  end

  Rails.logger.info("[covenant-assignees] filters assigneeOrGroup/assignedTo include CF «#{CovenantAssignees::CF_NAME}»")
rescue StandardError => e
  Rails.logger.warn("[covenant-assignees] filter patch failed: #{e.class}: #{e.message}")
end

def covenant_patch_wp_assignee_sync!
  return unless defined?(WorkPackage)

  unless defined?(CovenantWpAssigneesSync)
    Object.const_set(:CovenantWpAssigneesSync, Module.new do
      def custom_field_values=(values)
        CovenantAssignees.remember_executor_assignment!(self, values)
        super
      end

      def covenant_snapshot_executor_ids
        @covenant_executor_ids_was =
          if persisted?
            CovenantAssignees.db_user_ids(id)
          else
            []
          end
      end

      def covenant_before_save_sync_assignee
        if @covenant_executors_explicit
          ids = Array(@covenant_executors_ids)
          self.assigned_to_id = ids.first
          @covenant_skip_cf_backfill = ids.empty?
          return
        end

        @covenant_cf_cleared = CovenantAssignees.cf_cleared?(self)
        explicit_assignee = assigned_to_id_changed? && assigned_to_id.present?
        if @covenant_cf_cleared && !explicit_assignee
          self.assigned_to_id = nil
          @covenant_skip_cf_backfill = true
        else
          CovenantAssignees.sync_assigned_to!(self)
        end
      end

      def covenant_after_commit_assignees
        return if @covenant_overdue_status_flip

        if @covenant_skip_cf_backfill
          # Сток на before_save выкидывает снятые CV из association, destroy их
          # не всегда догоняет, а ensure_cf пишет assigned_to обратно. Один и остаётся.
          CovenantAssignees.replace_custom_values!(self, [])
          update_columns(assigned_to_id: nil)
        else
          CovenantAssignees.ensure_cf_from_assigned_to!(self)
        end
        custom_values.reset if respond_to?(:custom_values)
        send(:reset_custom_values_change_tracker) if respond_to?(:reset_custom_values_change_tracker, true)
        CovenantAssignees.mail_added!(self, @covenant_executor_ids_was)

        now = CovenantAssignees.executor_ids(self)
        # Не только «добавили id»: переназначение того же человека на родителе
        # даёт now == was, пустые дети иначе не заполняются.
        CovenantAssignees.cascade_to_empty_children!(self) if now.any?
      rescue StandardError => e
        Rails.logger.error("[covenant-assignees] after_commit wp=#{id}: #{e.class}: #{e.message}")
      ensure
        @covenant_executors_explicit = false
        @covenant_executors_ids = nil
        @covenant_skip_cf_backfill = false
      end
    end)
  end

  unless WorkPackage.included_modules.include?(CovenantWpAssigneesSync)
    WorkPackage.include(CovenantWpAssigneesSync)
    WorkPackage.before_validation :covenant_snapshot_executor_ids
    WorkPackage.before_save :covenant_before_save_sync_assignee
    WorkPackage.after_commit :covenant_after_commit_assignees
  end

  Rails.logger.info("[covenant-assignees] WP sync CF «#{CovenantAssignees::CF_NAME}» ↔ assigned_to")
rescue StandardError => e
  Rails.logger.warn("[covenant-assignees] WP sync patch failed: #{e.class}: #{e.message}")
end

# Дублирование в другое предприятие: «Исполнители» (CF, multi) и assigned_to/
# responsible копируются как есть, но эти люди почти никогда не участники
# целевого проекта → CreateService падает («… is not set to one of the
# allowed values», «Выбранный пользователь не может быть «Назначенный»…»).
# Для BulkCopyService это НЕ all-or-nothing: одна ошибка на потомке валит
# его id в nil, что дальше ломает вывод ошибки (work_package_path(nil)).
# Поэтому чистим невалидных исполнителей ДО create, а не лечим сообщение.
def covenant_patch_wp_copy_assignees!
  return unless defined?(WorkPackages::CopyService)

  unless defined?(CovenantWpCopyAssignees)
    Object.const_set(:CovenantWpCopyAssignees, Module.new do
      def copied_attributes(work_package, override)
        attributes = super

        # Bulk::CopyService передаёт override с символьным :project_id
        # (а не строковым "project_id", как в attributes_for_create).
        raw_target_id = override["project_id"] || override[:project_id]
        target_id = raw_target_id.presence&.to_i || work_package.project_id
        return attributes if target_id == work_package.project_id

        target_project = Project.find_by(id: target_id)
        return attributes unless target_project

        allowed = Principal.possible_assignee(target_project).pluck(:id).to_set

        cf = CovenantAssignees.custom_field
        cfv = attributes["custom_field_values"]
        if cf && cfv.is_a?(Hash) && cfv.key?(cf.id)
          cfv[cf.id] = Array(cfv[cf.id]).select { |uid| allowed.include?(uid.to_i) }
        end

        %w[assigned_to_id responsible_id].each do |key|
          next if attributes[key].blank?

          attributes[key] = nil unless allowed.include?(attributes[key].to_i)
        end

        attributes
      end
    end)
  end
  return if WorkPackages::CopyService.ancestors.include?(CovenantWpCopyAssignees)

  WorkPackages::CopyService.prepend(CovenantWpCopyAssignees)
  Rails.logger.info("[covenant-assignees] CopyService: strip assignees not in target project")
rescue StandardError => e
  Rails.logger.warn("[covenant-assignees] CopyService assignees patch failed: #{e.class}: #{e.message}")
end

Rails.application.config.to_prepare do
  CovenantAssignees.reset!
  covenant_patch_assignee_filters!
  covenant_patch_wp_assignee_sync!
  covenant_patch_wp_copy_assignees!
end

Rails.application.config.after_initialize do
  CovenantAssignees.reset!
  covenant_patch_assignee_filters!
  covenant_patch_wp_assignee_sync!
  covenant_patch_wp_copy_assignees!
end
