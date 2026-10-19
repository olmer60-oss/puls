# Запуск: bundle exec rails runner lib/tasks/pulse_overdue_checker.rb

Rails.logger.info "[Pulse-Cron] Начало проверки просроченных сдач предприятий..."

# 1. Динамически находим сущности метаданных
type_sundach = Type.find_by(name: "Сдача предприятия")
status_expected = Status.find_by(name: "Ожидается")
status_overdue = Status.find_by(name: "Просрочено")

# Если статуса "Просрочено" еще нет в глобальном списке, безопасно инициализируем его
if status_overdue.nil?
  status_overdue = Status.create!(name: "Просрочено", is_closed: false, is_readonly: false)
  Rails.logger.info "[Pulse-Cron] Создан новый глобальный статус 'Просрочено'"
end

# Находим кастомное поле "Внутренний срок"
internal_date_cf = WorkPackageCustomField.find_by(name: "Внутренний срок")

if type_sundach.nil? || status_expected.nil? || internal_date_cf.nil?
  Rails.logger.error "[Pulse-Cron] Критическая ошибка: Не найдены необходимые типы данных, статусы или кастомные поля!"
  exit 1
end

# 2. Выборка кандидатов на просрочку
# Выбираем задачи нужного типа в статусе "Ожидается"
work_packages = WorkPackage.where(type_id: type_sundach.id, status_id: status_expected.id)

updated_count = 0

work_packages.find_each do |wp|
  # Получаем значение кастомного поля "Внутренний срок"
  internal_date_value = wp.custom_value_for(internal_date_cf.id)&.value
  
  next if internal_date_value.blank?
  
  begin
    internal_date = Date.parse(internal_date_value)
    
    # Если внутренний срок меньше сегодняшнего дня — переводим в "Просрочено"
    if internal_date < Date.today
      Rails.logger.info "[Pulse-Cron] Задача ##{wp.id} ('#{wp.subject}') просрочена (Дедлайн: #{internal_date}). Обновление..."
      
      # Используем штатный UpdateService для сохранения истории изменений
      current_user = User.find_by(login: "admin") # Выполняем от имени администратора системы
      
      service_result = WorkPackages::UpdateService.new(
        user: current_user,
        work_package: wp
      ).call(
        status_id: status_overdue.id,
        journal_notes: "Системное уведомление: Внутренний срок сдачи контролируемых показателей (#{internal_date}) истек. Статус автоматически изменен на 'Просрочено'."
      )
      
      if service_result.success?
        updated_count += 1
      else
        Rails.logger.error "[Pulse-Cron] Не удалось обновить задачу ##{wp.id}: #{service_result.errors.full_messages.join(', ')}"
      end
    end
  rescue ArgumentError => e
    Rails.logger.error "[Pulse-Cron] Ошибка парсинга даты в задаче ##{wp.id}: #{e.message}"
  end
end

Rails.logger.info "[Pulse-Cron] Проверка завершена. Успешно переведено в статус 'Просрочено': #{updated_count} задач."
