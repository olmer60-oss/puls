# Инициализация ролевой модели системы Пульс v2
Rails.logger.info "[v2-roles] Инициализация ролевой модели системы Пульс v2..."

# 1. Списки разрешений (Permissions)
coordinator_permissions = [
  :view_work_packages, :add_work_packages, :edit_work_packages, :move_work_packages,
  :delete_work_packages, :manage_work_package_relations, :add_work_package_notes,
  :edit_work_package_notes, :view_work_package_watchers, :add_work_package_watchers,
  :delete_work_package_watchers, :export_work_packages, :save_queries, :manage_public_queries,
  :view_project, :edit_project, :select_project_modules
]

assignee_permissions = [
  :view_work_packages, 
  :edit_work_packages, 
  :add_work_package_notes, 
  :edit_own_work_package_notes,
  :view_project
]

# 2. Безопасное создание/обновление Роли Координатора
coordinator_role = Role.find_by(name: "Координатор")
if coordinator_role.nil?
  # Создаем через базовый Role и явно передаем тип проектной роли для прохождения валидации
  coordinator_role = Role.new(name: "Координатор", type: "ProjectRole")
end
coordinator_role.permissions = coordinator_permissions
coordinator_role.save!
Rails.logger.info "[v2-roles] Роль 'Координатор' успешно настроена"

# 3. Безопасное создание/обновление Роли Исполнителя
assignee_role = Role.find_by(name: "Исполнитель предприятия")
if assignee_role.nil?
  assignee_role = Role.new(name: "Исполнитель предприятия", type: "ProjectRole")
end
assignee_role.permissions = assignee_permissions
assignee_role.save!
Rails.logger.info "[v2-roles] Роль 'Исполнитель предприятия' успешно настроена"

# 4. Создание групп для интеграции с Active Directory
%w[AD_Pulse_Coordinators AD_Pulse_Performers_DSK1 AD_Pulse_Performers_DSK2].each do |group_name|
  group = Group.find_by(lastname: group_name)
  if group.nil?
    Group.create!(lastname: group_name)
    Rails.logger.info "[v2-roles] Создана пустая системная группа #{group_name}"
  end
end

Rails.logger.info "[v2-roles] Инициализация ролей успешно завершена! 🚀"
