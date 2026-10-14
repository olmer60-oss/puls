# frozen_string_literal: true

# Covenant: Community-only — без EE, лишних модулей; WP → «Ковенанты»; проекты → «Предприятия».

# OpenProject фильтрует locales — явно подключаем наш YAML (после crowdin по имени zzz_).
locale_file = Rails.root.join("config/locales/zzz_covenant.ru.yml")
if locale_file.exist?
  I18n.load_path << locale_file.to_s unless I18n.load_path.map(&:to_s).include?(locale_file.to_s)
end

COVENANT_LOCALE_REPLACEMENTS = [
  # кнопка хедера / тулбара до морфологии «задание»/«пакет»
  ["Создать новое задание", "Создать"],
  ["Создать новый пакет работ", "Создать"],
  ["Создать новый рабочий пакет", "Создать"],
  ["Create new work package", "Создать"],
  ["Новое задание", "Создать"],
  ["новое задание", "создать"],
  # миграция прошлых ярлыков «Задани*» / «Площадк*»
  ["Все площадки", "Все предприятия"],
  ["Мои площадки", "Мои предприятия"],
  ["Избранные площадки", "Избранное"],
  ["Архивные площадки", "Архив"],
  ["Новая площадка", "Новое предприятие"],
  ["Покинуть площадку", "Покинуть предприятие"],
  ["Настройки площадки", "Настройки предприятия"],
  ["Площадки", "Предприятия"],
  ["Площадка", "Предприятие"],
  ["площадок", "предприятий"],
  ["площадки", "предприятия"],
  ["Все задания", "Все ковенанты"],
  ["Все открытые", "Все ковенанты"],
  ["Задания", "Ковенанты"],
  ["Заданий", "Ковенант"],
  ["Задание", "Ковенанта"],
  ["Заданием", "Ковенантой"],
  ["Заданию", "Ковенанте"],
  ["Задании", "Ковенанте"],
  ["задания", "ковенанты"],
  ["заданий", "ковенант"],
  ["задание", "ковенанта"],
  ["заданием", "ковенантой"],
  ["заданию", "ковенанте"],
  ["задании", "ковенанте"],
  # OP originals → Ковенанты
  ["Пакеты работ", "Ковенанты"],
  ["пакеты работ", "ковенанты"],
  ["Пакетов работ", "Ковенант"],
  ["пакетов работ", "ковенант"],
  ["Пакета работ", "Ковенанты"],
  ["пакета работ", "ковенанты"],
  ["Пакетом работ", "Ковенантой"],
  ["пакетом работ", "ковенантой"],
  ["Пакету работ", "Ковенанте"],
  ["пакету работ", "ковенанте"],
  ["Пакет работ", "Ковенанта"],
  ["пакет работ", "ковенанта"],
  ["Рабочие пакеты", "Ковенанты"],
  ["рабочие пакеты", "ковенанты"],
  ["Рабочих пакетов", "Ковенант"],
  ["рабочих пакетов", "ковенант"],
  ["Рабочего пакета", "Ковенанты"],
  ["рабочего пакета", "ковенанты"],
  ["Рабочий пакет", "Ковенанта"],
  ["рабочий пакет", "ковенанта"],
  ["рабочем пакете", "ковенанте"],
  ["Рабочем пакете", "Ковенанте"],
  ["All projects", "Предприятия"],
  ["Все проекты", "Предприятия"],
  ["Активные проекты", "Все предприятия"],
  ["Мои проекты", "Мои предприятия"],
  ["Избранные проекты", "Избранное"],
  ["Архивные проекты", "Архив"],
  ["Деятельность", "История изменений"],
  ["деятельность", "история изменений"],
  ["Общая деятельность", "Общая история изменений"],
  ["All filters", "Все фильтры"],
  ["Dismiss alert", "Закрыть"],
  ["Dismiss", "Закрыть"],
  ["Favorites", "Избранное"],
  ["Leave project", "Покинуть предприятие"],
  ["Change password", "Сменить пароль"],
  ["Режим «Дзен» (только доска и часы)", "Режим на весь экран"],
  ["Zen mode", "Режим на весь экран"],
  ["One item selected", "Выбран 1 элемент"],
  ["проектов, использующих", "предприятий, использующих"],
  # колонки /projects (PM2 + hierarchy)
  ["Initiating", "Запуск"],
  ["Planning", "Планирование"],
  ["Executing", "Выполнение"],
  ["Closing", "Закрытие"],
  ["Hierarchy", "Иерархия"],
  ["Ready for Planning", "Готово к планированию"],
  ["Ready for Executing", "Готово к выполнению"],
  ["Ready for Closing", "Готово к закрытию"],
  # после морфологии пакет/задание → ковенанта (кнопка тулбара / aria)
  ["Создать новую ковенанту", "Создать"],
  ["Создать новый ковенанта", "Создать"],
  ["Создать новую ковенант", "Создать"],
  # иерархия / parent
  ["Установить родителя", "Сделать подзадачей"],
  ["Изменить родителя", "Изменить родительскую ковенанту"],
  ["Удалить родителя", "Убрать из подзадач"],
  ["Добавить существующего родителя", "Выбрать родительскую ковенанту"],
  ["Выберите нового родителя или нажмите escape, чтобы отменить.", "Выберите родительскую ковенанту или Escape для отмены."],
  ["Создать новый дочерний элемент", "Создать подзадачу"]
].freeze

def covenant_patch_frontend_locale!
  Dir[Rails.root.join("public/assets/frontend/src/locales/ru-*.js")].each do |path|
    marker = path.sub(/\.js\z/, ".covenant-patched")
    FileUtils.rm_f(marker) # always re-apply when initializer reloads with new dict
    raw = File.read(path)
    decoded = raw.gsub(/\\u([0-9a-fA-F]{4})/) { [::Regexp.last_match(1).to_i(16)].pack("U") }

    patched = decoded.dup
    COVENANT_LOCALE_REPLACEMENTS.each { |from, to| patched.gsub!(from, to) }

    next if patched == decoded && File.exist?(marker)

    encoded = patched.chars.map { |ch| ch.ord > 127 ? format("\\u%04X", ch.ord) : ch }.join
    File.write(path, encoded)
    File.write(marker, "patched\n")
    Rails.logger.info("[covenant] patched frontend locale #{File.basename(path)}")
  end
rescue StandardError => e
  Rails.logger.warn("[covenant] frontend locale patch failed: #{e.class}: #{e.message}")
end

def covenant_patch_help_menu!
  return unless defined?(Redmine::MenuManager::TopMenu::HelpMenu)

  Redmine::MenuManager::TopMenu::HelpMenu.module_eval do
    def render_help_top_menu_node(*)
      "".html_safe
    end

    def add_help_and_support_items(*)
      nil
    end
  end

  Rails.logger.info("[covenant] help button removed")
rescue StandardError => e
  Rails.logger.warn("[covenant] help menu patch failed: #{e.class}: #{e.message}")
end

# OpenProject падает на логине: more_top_menu_items пустой (login_required + anon),
# а module_top_menu_item_groups делает items.first.heading? без проверки.
def covenant_patch_module_menu!
  return unless defined?(Redmine::MenuManager::TopMenu::ModuleMenu)

  Redmine::MenuManager::TopMenu::ModuleMenu.module_eval do
    def module_top_menu_item_groups
      items = more_top_menu_items
      return [] if items.blank?

      item_groups = []

      unless items.first.heading?
        item_groups = [default_module_menu_group]
      end

      items.reduce(item_groups) do |groups, item|
        if item.heading?
          groups << { title: item.caption, items: [] }
        else
          groups.last[:items] << item
        end

        groups
      end
    end
  end

  Rails.logger.info("[covenant] module menu empty-safe")
rescue StandardError => e
  Rails.logger.warn("[covenant] module menu patch failed: #{e.class}: #{e.message}")
end

def covenant_deep_delete_menu_items!(menu_name, *names)
  root = Redmine::MenuManager.items(menu_name)
  return unless root

  names.flatten.each do |item_name|
    node = covenant_find_menu_node(root, item_name)
    next unless node&.parent

    node.parent.remove!(node)
  end
rescue StandardError => e
  Rails.logger.warn("[covenant] deep delete #{menu_name}/#{names.inspect} failed: #{e.class}: #{e.message}")
end

def covenant_find_menu_node(node, name)
  return node if node.name.to_sym == name.to_sym

  node.children.each do |child|
    found = covenant_find_menu_node(child, name)
    return found if found
  end
  nil
end

# У «Задания» убираем вложенный query-select и wp-query-menu — иначе drill-down
# прячет соседний пункт «История изменений».
def covenant_flatten_project_work_packages_menu!
  root = Redmine::MenuManager.items(:project_menu)
  return unless root

  wp = root.children.find { |n| n.name.to_sym == :work_packages }
  return unless wp

  wp.children.to_a.each { |child| wp.remove!(child) }

  if wp.html_options.is_a?(Hash)
    wp.html_options.delete(:"wp-query-menu")
    wp.html_options.delete("wp-query-menu")
  end

  Rails.logger.info("[covenant] project sidebar flat: Ковенанты + История изменений")
rescue StandardError => e
  Rails.logger.warn("[covenant] flatten WP menu failed: #{e.class}: #{e.message}")
end

def covenant_remove_menus!
  return unless defined?(Redmine::MenuManager)

  # Глобально: только Предприятия + История изменений (home/my_page убраны)
  Redmine::MenuManager.map :top_menu do |menu|
    %i[portfolios work_packages gantt help home my_page news].each { |i| menu.delete(i) }
  end

  Redmine::MenuManager.map :global_menu do |menu|
    %i[
      home my_page news my_time_tracking
      portfolios portfolios_query_select
      work_packages work_packages_query_select
      gantt global_gantt_query_select
      calendar_view team_planners boards
      meetings meetings_query_select
      cost_reports_global cost_reports_global_report_menu
    ].each { |i| menu.delete(i) }
  end
  # nested: mapper.delete ломает parent — удаляем через parent.remove!
  covenant_deep_delete_menu_items!(:global_menu, :activity_filters)

  Redmine::MenuManager.map :account_menu do |menu|
    %i[administration timers my_page my_account].each { |i| menu.delete(i) }
    # Шестерёнка → интерфейс; уведомления — в сайдбаре /my (my_menu :notifications)
    menu.push :my_account,
              { controller: "/my", action: "interface" },
              caption: :label_interface,
              icon: :gear,
              before: :logout,
              if: ->(_) { User.current.logged? }
  end

  # /my/*: Интерфейс + Уведомления (email через SMTP); остальной self-service вырезан
  Redmine::MenuManager.map :my_menu do |menu|
    %i[account working_hours locale security access_tokens sessions avatar].each do |i|
      menu.delete(i)
    end
  end

  Redmine::MenuManager.map :project_menu do |menu|
    # Только top-level: nested через mapper.delete даёт зомби
    %i[
      gantt roadmap documents documents_sub_menu
      calendar calendar_view news forums repository wiki
      budgets costs meetings board_view boards
      team_planner team_planner_view
      members members_menu settings overview
      ifc_models resource_management backlogs
    ].each { |i| menu.delete(i) }

    # Плоский сайдбар предприятия: Все предприятия → Ковенанты → История.
    # URL — строка /projects (Hash мержится с project_id → редирект на WP).
    # skip_permissions_check: иначе node_action_allowed?("/projects") в контексте
    # проекта ловит UnknownPermissionError и пункт просто не рендерится.
    menu.delete(:work_packages)
    menu.delete(:activity)
    menu.delete(:covenant_all_enterprises)
    menu.delete(:covenant_folders)

    menu.push :covenant_all_enterprises,
              "/projects",
              caption: :label_project_view_all,
              icon: "project",
              first: true,
              skip_permissions_check: true,
              if: ->(*) { User.current.logged? },
              html: { id: "main-menu-all-enterprises" }

    menu.push :covenant_folders,
              { controller: "/covenant_folders", action: "index" },
              caption: :label_covenant_folders,
              icon: "file-directory",
              after: :covenant_all_enterprises,
              skip_permissions_check: true,
              if: ->(*) { User.current.logged? },
              html: { id: "main-menu-covenant-folders", data: { turbo: false } }

    menu.push :work_packages,
              { controller: "/work_packages", action: "index" },
              caption: :label_work_package_plural,
              if: ->(project) { project.module_enabled?("work_package_tracking") },
              icon: "op-view-list",
              after: :covenant_folders,
              html: { id: "main-menu-work-packages" }

    menu.push :activity,
              { controller: "/activities", action: "index" },
              if: ->(project) { project.module_enabled?("activity") },
              caption: :label_activity,
              icon: "history",
              after: :work_packages
  end

  # Админка: прячем зоопарк настроек (роуты живы, если знать URL)
  Redmine::MenuManager.map :admin_menu do |menu|
    %i[
      admin_overview users_and_permissions user_settings users placeholder_users groups
      departments roles permissions_report user_avatars
      admin_work_packages work_packages_general types statuses priorities
      work_packages_identifier progress_tracking workflows custom_actions
      admin_projects_settings project_phase_definitions_settings
      project_custom_fields_settings new_project_settings project_lists_settings
      project_reserved_identifiers_settings
      custom_fields attribute_help_texts calendars_and_dates working_days_and_hours
      date_format icalendar ai mcp_configurations
      settings settings_general settings_languages settings_external_links
      settings_exports settings_repositories settings_experimental
      incoming_mails
      api_and_webhooks api authentication authentication_settings oauth_applications
      ldap_authentication scim_clients announcements admin_integrations
      custom_style colors enterprise import jira_import
      plugins backups info
    ].each { |i| menu.delete(i) }
  end

  # Вкладки карточки задания: без Вики
  Redmine::MenuManager.map :work_package_split_view do |menu|
    menu.delete(:wikis)
  end

  # Quick-add: без invite (кнопка патчится → новое задание)
  Redmine::MenuManager.map :quick_add_menu do |menu|
    menu.delete(:invite_user)
  end

  Rails.logger.info("[covenant] menus: enterprises + change history (no activity filters)")
rescue StandardError => e
  Rails.logger.warn("[covenant] remove menus failed: #{e.class}: #{e.message}")
end

# Сайдбар /projects: без «Мои» и без группы «Статус».
# main_static_filters в OP — private, method_defined? его не видит → alias не ставился.
def covenant_strip_project_status_sidebar!
  return unless defined?(Projects::Menu)

  unless defined?(CovenantProjectsMenu)
    Object.const_set(:CovenantProjectsMenu, Module.new do
      def main_static_filters
        static_filters [
          ::ProjectQueries::Static::ACTIVE,
          current_user.logged? ? ::ProjectQueries::Static::FAVORITED : nil,
          current_user.admin? ? ::ProjectQueries::Static::ARCHIVED : nil
        ].compact
      end

      def menu_items
        [
          OpenProject::Menu::MenuGroup.new(header: nil, children: main_static_filters),
          OpenProject::Menu::MenuGroup.new(header: I18n.t(:"projects.lists.my_lists"), children: my_filters),
          OpenProject::Menu::MenuGroup.new(header: I18n.t(:"projects.lists.shared"), children: shared_filters)
        ]
      end
    end)
  end

  unless Projects::Menu.ancestors.include?(CovenantProjectsMenu)
    Projects::Menu.prepend(CovenantProjectsMenu)
  end

  Rails.logger.info("[covenant] projects sidebar: no my-list, no status group")
rescue StandardError => e
  Rails.logger.warn("[covenant] strip project status sidebar failed: #{e.class}: #{e.message}")
end

# PM2-фазы из сида часто остаются на EN → колонки Initiating/Planning/…
COVENANT_PROJECT_PHASE_NAME_MAP = {
  "Initiating" => "Запуск",
  "Planning" => "Планирование",
  "Executing" => "Выполнение",
  "Closing" => "Закрытие"
}.freeze
COVENANT_PROJECT_PHASE_GATE_MAP = {
  "Ready for Planning" => "Готово к планированию",
  "Ready for Executing" => "Готово к выполнению",
  "Ready for Closing" => "Готово к закрытию"
}.freeze

def covenant_localize_project_phases!
  return unless defined?(Project::PhaseDefinition)

  updated = 0
  Project::PhaseDefinition.find_each do |phase|
    attrs = {}
    ru_name = COVENANT_PROJECT_PHASE_NAME_MAP[phase.name]
    attrs[:name] = ru_name if ru_name && phase.name != ru_name

    if phase.start_gate_name.present?
      ru_gate = COVENANT_PROJECT_PHASE_GATE_MAP[phase.start_gate_name]
      attrs[:start_gate_name] = ru_gate if ru_gate && phase.start_gate_name != ru_gate
    end
    if phase.finish_gate_name.present?
      ru_gate = COVENANT_PROJECT_PHASE_GATE_MAP[phase.finish_gate_name]
      attrs[:finish_gate_name] = ru_gate if ru_gate && phase.finish_gate_name != ru_gate
    end

    next if attrs.empty?

    phase.update_columns(attrs)
    updated += 1
  end

  Rails.logger.info("[covenant] project phases localized (#{updated})")
rescue StandardError => e
  Rails.logger.warn("[covenant] localize project phases failed: #{e.class}: #{e.message}")
end

# /projects → «Настроить вид» / «Добавить столбец»: без бюджетов и фазы «Планирование».
COVENANT_HIDDEN_PROJECT_PHASE_COLUMN_NAMES = ["Планирование", "Planning"].freeze
COVENANT_HIDDEN_PROJECT_SELECT_CLASSES = %w[
  Queries::Projects::Selects::BudgetAvailable
  Queries::Projects::Selects::BudgetSpent
  Queries::Projects::Selects::BudgetSpentRatio
  Queries::Projects::Selects::BudgetPlanned
].freeze

def covenant_strip_project_list_columns!
  return unless defined?(ProjectQuery) && defined?(Queries::Register)

  if Queries::Register.selects.is_a?(Hash) && Queries::Register.selects[ProjectQuery]
    before = Queries::Register.selects[ProjectQuery].size
    Queries::Register.selects[ProjectQuery].reject! do |klass|
      COVENANT_HIDDEN_PROJECT_SELECT_CLASSES.include?(klass.name)
    end
    removed = before - Queries::Register.selects[ProjectQuery].size
  end

  if defined?(Queries::Projects::Selects::ProjectPhase)
    unless defined?(CovenantHideProjectPhaseColumns)
      Object.const_set(:CovenantHideProjectPhaseColumns, Module.new do
        def all_available
          super.reject do |select|
            name = select.project_phase_definition&.name.to_s
            COVENANT_HIDDEN_PROJECT_PHASE_COLUMN_NAMES.include?(name)
          end
        end
      end)
    end
    unless Queries::Projects::Selects::ProjectPhase.singleton_class.ancestors.include?(CovenantHideProjectPhaseColumns)
      Queries::Projects::Selects::ProjectPhase.singleton_class.prepend(CovenantHideProjectPhaseColumns)
    end
  end

  # убрать бюджеты из уже сохранённых project queries / settings
  budget_attrs = %w[budget_available budget_spent budget_spent_ratio budget_planned]
  if defined?(Setting) && Setting.respond_to?(:enabled_projects_columns)
    cols = Array(Setting.enabled_projects_columns).map(&:to_s)
    cleaned = cols - budget_attrs
    if cleaned != cols
      begin
        Setting.enabled_projects_columns = cleaned
      rescue Setting::NotWritableError
        # ignore
      end
    end
  end

  if defined?(ProjectQuery)
    ProjectQuery.find_each do |q|
      next unless q.respond_to?(:selects)

      sels = Array(q.selects).map(&:to_s)
      next if (sels & budget_attrs).empty?

      q.selects = sels - budget_attrs
      q.save(validate: false)
    end
  end

  Rails.logger.info("[covenant] project list columns stripped (budgets#{removed.to_i.positive? ? ", -#{removed}" : ""}, hide phase Планирование)")
rescue StandardError => e
  Rails.logger.warn("[covenant] strip project list columns failed: #{e.class}: #{e.message}")
end

# Вики в карточке задания: выключаем провайдеры (вкладка завязана на Wikis::Provider.enabled)
def covenant_disable_wikis!
  return unless defined?(Wikis::Provider)

  disabled = Wikis::Provider.where(enabled: true).update_all(enabled: false)
  Rails.logger.info("[covenant] wikis providers disabled (#{disabled})")
rescue StandardError => e
  Rails.logger.warn("[covenant] disable wikis failed: #{e.class}: #{e.message}")
end

def covenant_default_enterprise_path
  # Своё предприятие → папки. Без membership — /projects, не чужой pao-koks (404).
  covenant_user_landing_path_for(defined?(User) ? User.current : nil)
rescue StandardError
  "/projects"
end

def covenant_redirect_home!
  return unless defined?(HomescreenController)
  return if defined?(CovenantHomescreenRedirect) && HomescreenController.ancestors.include?(CovenantHomescreenRedirect)

  unless defined?(CovenantHomescreenRedirect)
    Object.const_set(:CovenantHomescreenRedirect, Module.new do
      def index
        redirect_to("/projects", status: :see_other)
      end
    end)
  end
  HomescreenController.prepend(CovenantHomescreenRedirect)
  Rails.logger.info("[covenant] / → /projects")
rescue StandardError => e
  Rails.logger.warn("[covenant] home redirect failed: #{e.class}: #{e.message}")
end

# /projects/:id (overview) → сразу задания
def covenant_redirect_project_to_work_packages!
  return unless defined?(Overviews::OverviewsController)
  return if defined?(CovenantOverviewRedirect) &&
            Overviews::OverviewsController.ancestors.include?(CovenantOverviewRedirect)

  unless defined?(CovenantOverviewRedirect)
    Object.const_set(:CovenantOverviewRedirect, Module.new do
      # Сток: jump → allowed_in_project?(url пункта). У «Папки» нет permission,
      # raise_on_unknown даёт 500. Админ чаще попадает сюда из списка предприятий.
      def jump_to_project_menu_item
        return if covenant_redirect_known_jump!

        super
      rescue StandardError => e
        Rails.logger.warn("[covenant] jump=#{params[:jump]} failed: #{e.class}: #{e.message}")
        covenant_redirect_project_home!
      end

      def show
        return if covenant_redirect_known_jump!

        if params[:jump].present? && respond_to?(:redirect_to_project_menu_item, true)
          jumped = redirect_to_project_menu_item(@project, params[:jump])
          return if jumped
        end

        covenant_redirect_project_home!
      rescue StandardError => e
        Rails.logger.warn("[covenant] project show failed: #{e.class}: #{e.message}")
        covenant_redirect_project_home!
      end

      def covenant_redirect_known_jump!
        return false unless params[:jump].to_s == "covenant_folders" && @project

        covenant_redirect_project_home!
        true
      end

      def covenant_redirect_project_home!
        return if performed?

        if @project&.parent_id.nil?
          redirect_to(covenant_folders_path_for(@project), status: :see_other)
        elsif @project
          redirect_to(project_work_packages_path(@project), status: :see_other)
        end
      end
    end)
  end

  Overviews::OverviewsController.prepend(CovenantOverviewRedirect)
  Rails.logger.info("[covenant] /projects/:id → folders (root) / work_packages (folder)")
rescue StandardError => e
  Rails.logger.warn("[covenant] project overview redirect failed: #{e.class}: #{e.message}")
end

# Прямой /projects/:id/work_packages у завода → папки
def covenant_redirect_root_wp_to_folders!
  return unless defined?(WorkPackagesController)
  return if defined?(CovenantRootWpToFolders) &&
            WorkPackagesController.ancestors.include?(CovenantRootWpToFolders)

  unless defined?(CovenantRootWpToFolders)
    Object.const_set(:CovenantRootWpToFolders, Module.new do
      def index
        # Корень: таблица ковенант завода («Без папки»). На папки ведёт overview / after_login.
        super
      end
    end)
  end

  WorkPackagesController.prepend(CovenantRootWpToFolders)
  Rails.logger.info("[covenant] root /work_packages → folders")
rescue StandardError => e
  Rails.logger.warn("[covenant] root WP→folders patch failed: #{e.class}: #{e.message}")
end

# /projects: только заводы (без скрытых папок-подпроектов)
def covenant_project_list_roots_only!
  return unless defined?(ProjectQueries::Static)
  return if defined?(CovenantProjectStaticRoots) &&
            ProjectQueries::Static.singleton_class.ancestors.include?(CovenantProjectStaticRoots)

  unless defined?(CovenantProjectStaticRoots)
    Object.const_set(:CovenantProjectStaticRoots, Module.new do
      def list_with(name, &)
        super(name) do |query|
          yield query
          query.where("parent_id", "!*", [])
        end
      end
    end)
  end

  ProjectQueries::Static.singleton_class.prepend(CovenantProjectStaticRoots)
  Rails.logger.info("[covenant] /projects lists: parent_id IS NULL")
rescue StandardError => e
  Rails.logger.warn("[covenant] project list roots patch failed: #{e.class}: #{e.message}")
end

def covenant_hide_my_page!
  return unless defined?(My::PageController)
  return if defined?(CovenantMyPageRedirect) && My::PageController.ancestors.include?(CovenantMyPageRedirect)

  unless defined?(CovenantMyPageRedirect)
    Object.const_set(:CovenantMyPageRedirect, Module.new do
      def show
        redirect_to("/projects", status: :see_other)
      end
    end)
  end

  My::PageController.prepend(CovenantMyPageRedirect)
  Rails.logger.info("[covenant] /my/page → /projects")
rescue StandardError => e
  Rails.logger.warn("[covenant] my/page hide failed: #{e.class}: #{e.message}")
end

# /header/projects(/frame) — фрагменты селектора предприятий (layout: false).
# Прямой заход в браузере → редирект. НЕ трогаем:
# - Turbo-Frame (обёртка дропдауна)
# - fetch() из FilterableTreeView (Accept: text/html, без Turbo-Frame / Sec-Fetch-Mode: navigate)
def covenant_redirect_naked_header_projects!
  return unless defined?(Header::ProjectsController)
  return if defined?(CovenantHeaderProjectsFullPageRedirect) &&
            Header::ProjectsController.ancestors.include?(CovenantHeaderProjectsFullPageRedirect)

  unless defined?(CovenantHeaderProjectsFullPageRedirect)
    Object.const_set(:CovenantHeaderProjectsFullPageRedirect, Module.new do
      def index
        return super unless covenant_header_projects_full_page_navigation?

        redirect_to(covenant_default_enterprise_path, status: :see_other)
      end

      def frame
        return super unless covenant_header_projects_full_page_navigation?

        redirect_to(covenant_default_enterprise_path, status: :see_other)
      end

      private

      def covenant_header_projects_full_page_navigation?
        return false if turbo_frame_request?

        mode = request.headers["Sec-Fetch-Mode"].to_s
        # FilterableTreeView: fetch() → cors/same-origin; адресная строка → navigate
        return false if mode.present? && mode != "navigate"

        dest = request.headers["Sec-Fetch-Dest"].to_s
        return false if dest == "empty"

        true
      end
    end)
  end

  Header::ProjectsController.prepend(CovenantHeaderProjectsFullPageRedirect)
  Rails.logger.info("[covenant] /header/projects* full-page → user enterprise")
rescue StandardError => e
  Rails.logger.warn("[covenant] header projects redirect failed: #{e.class}: #{e.message}")
end

# Учётка из AD: вырезаем /my/account, /my/security, токены и прочий self-service.
# Оставляем /my/interface + /my/notifications (email через SMTP).
def covenant_strip_my_account!
  covenant_patch_look_and_feel_form!
  covenant_redirect_stripped_my_pages!
  Rails.logger.info("[covenant] my account stripped → interface + notifications")
rescue StandardError => e
  Rails.logger.warn("[covenant] strip my account failed: #{e.class}: #{e.message}")
end

def covenant_patch_look_and_feel_form!
  return unless defined?(My::LookAndFeelForm)

  My::LookAndFeelForm.class_eval do
    form do |f|
      f.fieldset_group(title: helpers.t("activerecord.attributes.user_preference.header_look_and_feel")) do |fg|
        fg.select_list(
          name: :theme,
          label: attribute_name(:theme),
          caption: attribute_name(:mode_guideline),
          required: true,
          include_blank: false,
          input_width: :small,
          data: {
            my__look_and_feel_target: "themeSelect",
            action: "my--look-and-feel#updateContrastOptions"
          }
        ) do |select|
          theme_options_for_select.each { |(label, value)| select.option(value:, label:) }
        end

        fg.check_box_group(data: { my__look_and_feel_target: "autoThemeContrast" }) do |group|
          group.check_box name: :force_light_theme_contrast,
                          label: attribute_name(:force_light_theme_contrast),
                          caption: attribute_name(:force_light_theme_contrast_caption)
          group.check_box name: :force_dark_theme_contrast,
                          label: attribute_name(:force_dark_theme_contrast),
                          caption: attribute_name(:force_dark_theme_contrast_caption)
        end

        fg.check_box_group(data: { my__look_and_feel_target: "singleThemeContrast" }) do |group|
          group.check_box name: :increase_theme_contrast,
                          label: attribute_name(:increase_contrast),
                          caption: attribute_name(:increase_contrast_caption)
        end

        fg.submit(name: :submit,
                  label: attribute_name(:button_update_look_and_feel),
                  scheme: :default)
      end
    end
  end
end

def covenant_redirect_stripped_my_pages!
  return unless defined?(MyController)

  unless defined?(CovenantMyAccountStrip)
    Object.const_set(:CovenantMyAccountStrip, Module.new do
      %i[account locale security password working_hours non_working_times].each do |action|
        define_method(action) do
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end
      end

      def write_settings
        result = Users::UpdateService
                   .new(user: current_user, model: current_user)
                   .call(user_params)

        if result&.success
          flash[:notice] = notice_account_updated
          handle_email_changes
        else
          flash[:error] = error_account_update_failed(result)
        end

        redirect_back_or_to({ controller: "/my", action: "interface" })
      end
    end)
  end

  unless MyController.ancestors.include?(CovenantMyAccountStrip)
    MyController.prepend(CovenantMyAccountStrip)
  end

  if defined?(My::AccessTokensController)
    unless defined?(CovenantAccessTokensRedirect)
      Object.const_set(:CovenantAccessTokensRedirect, Module.new do
        def index
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end
      end)
    end
    unless My::AccessTokensController.ancestors.include?(CovenantAccessTokensRedirect)
      My::AccessTokensController.prepend(CovenantAccessTokensRedirect)
    end
  end

  if defined?(My::SessionsController)
    unless defined?(CovenantSessionsRedirect)
      Object.const_set(:CovenantSessionsRedirect, Module.new do
        def index
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end

        def destroy
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end
      end)
    end
    unless My::SessionsController.ancestors.include?(CovenantSessionsRedirect)
      My::SessionsController.prepend(CovenantSessionsRedirect)
    end
  end

  if defined?(Avatars::MyAvatarController)
    unless defined?(CovenantMyAvatarRedirect)
      Object.const_set(:CovenantMyAvatarRedirect, Module.new do
        # BaseController#ensure_enabled иначе даёт 404 до show
        def ensure_enabled
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end

        def show
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end

        def update
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end

        def destroy
          redirect_to({ controller: "/my", action: "interface" }, status: :see_other)
        end
      end)
    end
    unless Avatars::MyAvatarController.ancestors.include?(CovenantMyAvatarRedirect)
      Avatars::MyAvatarController.prepend(CovenantMyAvatarRedirect)
    end
  end
end

# Только letter-аватар (первая буква имени): без Gravatar / локальных загрузок.
# Фронт всё равно дергает GET /api/v3/users/:id/avatar — глушим запрос + отдаём SVG вместо 404.
def covenant_force_letter_avatars!
  return unless defined?(Setting) && defined?(OpenProject::Avatars::AvatarManager)

  desired = { "enable_gravatars" => false, "enable_local_avatars" => false }
  current = (Setting.plugin_openproject_avatars || {}).stringify_keys
  if current["enable_gravatars"].to_s != "false" || current["enable_local_avatars"].to_s != "false"
    Setting.plugin_openproject_avatars = current.merge(desired)
  end

  if defined?(AvatarHelper)
    AvatarHelper.module_eval do
      # Никаких URL аватарок — только буква
      def avatar_url(_user, _options = {})
        nil
      end

      # Буква аватара из firstname (User#name у нас = email)
      def principal_hash(user)
        principal_type = API::V3::Principals::PrincipalType.for(user)
        letter_source =
          if user.respond_to?(:firstname) && user.firstname.present?
            user.firstname
          else
            user.name
          end

        {
          href: API::V3::Utilities::PathHelper::ApiV3Path.send(principal_type, user.id),
          name: letter_source,
          id: user.id
        }
      end
    end
  end

  covenant_patch_avatar_api_letter_svg!
  covenant_patch_avatar_frontend_js!

  Rails.logger.info("[covenant] avatars → letter only (no gravatar/local, no 404)")
rescue StandardError => e
  Rails.logger.warn("[covenant] letter avatars failed: #{e.class}: #{e.message}")
end

def covenant_patch_avatar_api_letter_svg!
  path = Rails.root.join("modules/avatars/lib/api/v3/users/user_avatar_api.rb")
  return unless path.exist?

  raw = File.read(path)
  return if raw.include?("covenant_letter_avatar_svg")

  patched = raw.sub(
    /else\s*\n\s*status 404\s*\n\s*end/,
    <<~'RUBY'.rstrip
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
    RUBY
  )

  return if patched == raw

  File.write(path, patched)
  Rails.logger.info("[covenant] UserAvatarAPI → letter SVG (needs boot)")
rescue StandardError => e
  Rails.logger.warn("[covenant] avatar API patch failed: #{e.class}: #{e.message}")
end

def covenant_patch_avatar_frontend_js!
  Dir[Rails.root.join("public/assets/frontend/chunk-*.js")].each do |path|
    marker = "#{path}.covenant-no-avatar-fetch"
    next if File.exist?(marker)

    raw = File.read(path)
    next unless raw.include?("userAvatarUrl(principal)") && raw.include?("renderUserAvatar")

    patched = raw.dup
    # Не дергаем /api/v3/users/:id/avatar — остаётся letter fallback
    patched.sub!(
      /userAvatarUrl\(principal\)\s*\{\s*const id =/,
      "userAvatarUrl(principal){return null;const id="
    )
    next if patched == raw

    File.write(path, patched)
    File.write(marker, "patched\n")
    Rails.logger.info("[covenant] patched avatar JS #{File.basename(path)}")
  end
rescue StandardError => e
  Rails.logger.warn("[covenant] avatar JS patch failed: #{e.class}: #{e.message}")
end

COVENANT_STATUS_NAMES = %w[Запрошен Предоставлен Просрочено].freeze

# Сток OP (New / In progress / Closed / …) остаётся в БД и всплывает
# на копировании в другое предприятие: MovesController берёт
# Workflow.available_statuses по ролям, без ограничения типом «Запрос».
def covenant_purge_extra_statuses!
  return unless defined?(Status) && defined?(WorkPackage)

  if (st_old = Status.find_by(name: "Отклонено"))
    st_old.name = "Просрочено"
    st_old.is_closed = true
    st_old.position = 3
    st_old.save(validate: false)
  end

  requested = Status.find_by(name: "Запрошен")
  provided  = Status.find_by(name: "Предоставлен")
  overdue   = Status.find_by(name: "Просрочено")
  return unless requested && provided && overdue

  extras = Status.where.not(name: COVENANT_STATUS_NAMES)
  extras.find_each do |st|
    target =
      if st.name.match?(/\A(Rejected|Отклонен[оа]?)\z/i)
        overdue
      elsif st.is_closed?
        provided
      else
        requested
      end
    moved = WorkPackage.where(status_id: st.id).update_all(status_id: target.id)
    if defined?(Workflow)
      Workflow.where(old_status_id: st.id).or(Workflow.where(new_status_id: st.id)).delete_all
    end
    name = st.name
    if st.destroy
      Rails.logger.info("[covenant] status «#{name}» removed (wp_moved=#{moved} → #{target.name})")
    else
      Rails.logger.warn("[covenant] status «#{name}» not destroyed: #{st.errors.full_messages.join(", ")}")
    end
  end

  if defined?(Workflow)
    unless defined?(CovenantWorkflowStatuses) && Workflow.singleton_class.ancestors.include?(CovenantWorkflowStatuses)
      unless defined?(CovenantWorkflowStatuses)
        Object.const_set(:CovenantWorkflowStatuses, Module.new do
          def available_statuses(project, user = User.current)
            super.select { |s| COVENANT_STATUS_NAMES.include?(s.name) }
          end
        end)
      end
      Workflow.singleton_class.prepend(CovenantWorkflowStatuses)
    end
  end

  Rails.logger.info("[covenant] statuses kept: #{COVENANT_STATUS_NAMES.join(", ")}")
rescue StandardError => e
  Rails.logger.warn("[covenant] purge extra statuses failed: #{e.class}: #{e.message}")
end

COVENANT_PRIORITY_NAMES = %w[Низкий Обычный Высокий Срочный].freeze
COVENANT_PRIORITY_MAP = {
  "Low" => "Низкий",
  "Normal" => "Обычный",
  "Default" => "Обычный",
  "Стандартный" => "Обычный",
  "Нормальный" => "Обычный",
  "High" => "Высокий",
  "Immediate" => "Срочный",
  "Urgent" => "Срочный",
  "Немедленный" => "Срочный"
}.freeze

def covenant_fix_priorities!
  return unless defined?(IssuePriority)

  IssuePriority.update_all(is_default: false)

  {
    "Низкий" => 1,
    "Обычный" => 2,
    "Высокий" => 3,
    "Срочный" => 4
  }.each do |name, position|
    pr = IssuePriority.find_or_initialize_by(name:)
    pr.active = true
    pr.position = position
    pr.is_default = (name == "Обычный")
    pr.save(validate: false)
  end

  keep = IssuePriority.where(name: COVENANT_PRIORITY_NAMES).index_by(&:name)
  extras = IssuePriority.where.not(name: COVENANT_PRIORITY_NAMES)
  extras.find_each do |pr|
    target_name = COVENANT_PRIORITY_MAP[pr.name] || "Обычный"
    target = keep[target_name] || keep["Обычный"]
    moved = 0
    moved = WorkPackage.where(priority_id: pr.id).update_all(priority_id: target.id) if target
    name = pr.name
    if pr.destroy
      Rails.logger.info("[covenant] priority «#{name}» removed (wp_moved=#{moved} → #{target_name})")
    else
      Rails.logger.warn("[covenant] priority «#{name}» not destroyed: #{pr.errors.full_messages.join(", ")}")
    end
  end

  Rails.logger.info("[covenant] priorities kept: #{COVENANT_PRIORITY_NAMES.join(", ")}")
rescue StandardError => e
  Rails.logger.warn("[covenant] fix priorities failed: #{e.class}: #{e.message}")
end

# CopyService выкидывает start_date/due_date, если они не writable (auto-schedule).
# duration НЕ копируем: при обеих датах сток его удаляет, иначе mismatch → create fail → id nil.
def covenant_patch_wp_copy_dates!
  return unless defined?(WorkPackages::CopyService)

  unless defined?(CovenantWpCopyDates)
    Object.const_set(:CovenantWpCopyDates, Module.new do
      def copied_attributes(work_package, override)
        attributes = super

        attributes["start_date"] = work_package.start_date if attributes["start_date"].blank?
        attributes["due_date"] = work_package.due_date if attributes["due_date"].blank?

        if attributes["start_date"].present? || attributes["due_date"].present?
          attributes["schedule_manually"] = true
          attributes.delete("duration")
        end

        attributes
      end
    end)
  end
  unless WorkPackages::CopyService.ancestors.include?(CovenantWpCopyDates)
    WorkPackages::CopyService.prepend(CovenantWpCopyDates)
  end

  if defined?(WorkPackages::BulkJob)
    unless defined?(CovenantBulkCopyRedirect)
      Object.const_set(:CovenantBulkCopyRedirect, Module.new do
        def redirect_path(call, follow)
          if follow && call.success? && work_packages.size == 1
            copied = call.dependent_results.first&.result
            if copied.respond_to?(:id) && copied.id
              return url_helpers.work_package_path(copied)
            end

            return url_helpers.project_work_packages_path(target_project || project)
          end

          super
        end
      end)
    end
    unless WorkPackages::BulkJob.ancestors.include?(CovenantBulkCopyRedirect)
      WorkPackages::BulkJob.prepend(CovenantBulkCopyRedirect)
    end
  end

  return unless defined?(WorkPackages::MovesController)

  unless defined?(CovenantMoveDatesHelper)
    Object.const_set(:CovenantMoveDatesHelper, Module.new do
      def covenant_move_date(attr)
        wps = instance_variable_get(:@work_packages)
        return "" if wps.blank?

        dates = wps.map { |wp| wp.public_send(attr) }.uniq
        return "" if dates.size != 1 || dates.first.blank?

        date = dates.first
        date.respond_to?(:iso8601) ? date.iso8601 : date.to_s
      end
    end)
  end
  unless WorkPackages::MovesController.included_modules.include?(CovenantMoveDatesHelper)
    WorkPackages::MovesController.include(CovenantMoveDatesHelper)
    WorkPackages::MovesController.helper_method :covenant_move_date
  end

  path = Rails.root.join("app/views/work_packages/moves/new.html.erb")
  if path.exist?
    raw = File.read(path)
    unless raw.include?("covenant_move_date")
      patched = raw.dup
      patched.sub!(
        /id: ['"]start_date['"],\s*name: ['"]start_date['"]/,
        'id: "start_date", name: "start_date", value: covenant_move_date(:start_date)'
      )
      patched.sub!(
        /id: ['"]due_date['"],\s*name: ['"]due_date['"]/,
        'id: "due_date", name: "due_date", value: covenant_move_date(:due_date)'
      )
      if patched != raw
        File.write(path, patched)
        Rails.logger.info("[covenant] move form date pickers prefilled from source")
      end
    end
  end

  Rails.logger.info("[covenant] WP copy keeps start_date/due_date")
rescue StandardError => e
  Rails.logger.warn("[covenant] WP copy dates patch failed: #{e.class}: #{e.message}")
end

# Setting/ENV уже верные, но ActionMailer иногда остаётся на Rails-default localhost:25.
def covenant_reload_mailer_settings!
  return unless defined?(Setting) && Setting.respond_to?(:reload_mailer_settings!)
  return if Setting.email_delivery_method.blank?

  Setting.reload_mailer_settings!
  addr = ActionMailer::Base.smtp_settings[:address]
  Rails.logger.info("[covenant] mailer reloaded method=#{Setting.email_delivery_method} smtp=#{addr.inspect}")
rescue StandardError => e
  Rails.logger.warn("[covenant] mailer reload failed: #{e.class}: #{e.message}")
end

def covenant_localize_dismiss!
  if defined?(Primer::Alpha::Banner) &&
     Primer::Alpha::Banner.const_defined?(:DEFAULT_DISMISS_LABEL, false)
    Primer::Alpha::Banner.send(:remove_const, :DEFAULT_DISMISS_LABEL)
    Primer::Alpha::Banner.const_set(:DEFAULT_DISMISS_LABEL, "Закрыть")
  end

  # Primer Flash: aria-label зашит в gem erb
  gem_path = Gem.loaded_specs["openproject-primer_view_components"]&.full_gem_path
  if gem_path
    erb = File.join(gem_path, "app/components/primer/beta/flash.html.erb")
    if File.exist?(erb)
      raw = File.read(erb)
      patched = raw.gsub("Dismiss alert", "Закрыть").gsub('"Dismiss"', '"Закрыть"')
      File.write(erb, patched) if patched != raw
    end
  end

  Rails.logger.info("[covenant] Dismiss → Закрыть")
rescue StandardError => e
  Rails.logger.warn("[covenant] localize dismiss failed: #{e.class}: #{e.message}")
end

def covenant_set_landing_urls!
  return unless defined?(Setting)

  Setting.after_login_default_redirect_url = "/projects"
  Rails.logger.info("[covenant] after_login → #{Setting.after_login_default_redirect_url}")
rescue StandardError => e
  Rails.logger.warn("[covenant] landing urls failed: #{e.class}: #{e.message}")
end

# Выпилено навсегда: регистрация и «забыли пароль» (учётки из AD / админки).
def covenant_disable_self_service_auth!
  if defined?(Setting)
    begin
      Setting.lost_password = false if Setting.respond_to?(:lost_password=)
    rescue Setting::NotWritableError
      # уже задано env'ом
    end
    begin
      Setting.self_registration = 0 if Setting.respond_to?(:self_registration=)
    rescue Setting::NotWritableError
      # уже задано env'ом
    end
  end

  return unless defined?(AccountController)

  unless defined?(CovenantBlockSelfServiceAuth)
    Object.const_set(:CovenantBlockSelfServiceAuth, Module.new do
      %i[register lost_password change_password_activation activate].each do |action|
        define_method(action) { redirect_to(signin_path, status: :see_other) }
      end
    end)
  end
  unless AccountController.ancestors.include?(CovenantBlockSelfServiceAuth)
    AccountController.prepend(CovenantBlockSelfServiceAuth)
  end

  Rails.logger.info(
    "[covenant] login: no register / lost_password " \
    "(lost=#{Setting.lost_password.inspect} self_reg=#{Setting.self_registration.inspect})"
  )
rescue StandardError => e
  Rails.logger.warn("[covenant] disable self-service auth failed: #{e.class}: #{e.message}")
end

# Дефолтные колонки таблицы заданий (для default-query и пустых column_names).
# «Заблокирован» не в дефолте — поле/фильтр остаются, колонку можно включить вручную.
def covenant_default_wp_column_names
  cols = %w[id subject status]
  exec = WorkPackageCustomField.find_by(name: "Исполнители") if defined?(WorkPackageCustomField)
  cols << (exec ? "cf_#{exec.id}" : "assigned_to")
  cols << "due_date"
  cols
end

def covenant_enterprise_project_ids
  ad_catalog = [Rails.root.join("custom/covenant_ad.rb"), Pathname.new("/app/custom/covenant_ad.rb")].find(&:exist?)
  load ad_catalog.to_s if ad_catalog && !defined?(CovenantAd)

  ids = []
  enterprises = defined?(CovenantAd) ? CovenantAd::ENTERPRISES : []
  enterprises.each do |ent|
    root = Project.find_by(identifier: ent[:identifier])
    next unless root

    ids << root.id
    next unless root.lft && root.rgt

    ids.concat(
      Project.active.where(lft: root.lft..root.rgt).pluck(:id)
    )
  end
  ids.uniq.presence ||
    Project.where(identifier: %w[
      pao-koks ao-tulachermet ao-kmaruda ooo-uchastok-koksovy
      ooo-pmh-vtormet ooo-pmh-infotech ooo-uk-pmh
    ]).pluck(:id)
end

def covenant_set_default_wp_columns!
  return unless defined?(Setting) && defined?(Query)

  cols = covenant_default_wp_column_names
  current = Array(Setting.work_package_list_default_columns).map(&:to_s)
  if current != cols
    Setting.work_package_list_default_columns = cols
  end

  # Колонки у сохранённых представлений. Фильтры НЕ трогаем.
  # Иерархия вкл: родитель = папка, дети = подзадачи.
  updated = 0
  Query.where(project_id: covenant_enterprise_project_ids).find_each do |query|
    desired = cols.map(&:to_sym)
    changed = false

    if query.column_names.map(&:to_sym) != desired
      query.column_names = desired
      changed = true
    end
    unless query.show_hierarchies
      query.show_hierarchies = true
      changed = true
    end
    next unless changed

    query.save(validate: false)
    updated += 1
  end

  Rails.logger.info("[covenant] WP default columns=#{cols.join(",")} queries_updated=#{updated}")
rescue StandardError => e
  Rails.logger.warn("[covenant] default WP columns failed: #{e.class}: #{e.message}")
end

# По умолчанию — все задания (без status=open и прочих фильтров).
def covenant_no_default_wp_filters!
  return unless defined?(Query)

  unless defined?(CovenantQueryNoDefaultFilter)
    Object.const_set(:CovenantQueryNoDefaultFilter, Module.new do
      def add_default_filter
        # намеренно пусто: открываем полный список
      end
    end)
  end
  Query.prepend(CovenantQueryNoDefaultFilter) unless Query.ancestors.include?(CovenantQueryNoDefaultFilter)

  if defined?(WorkPackages::DefaultQueryGeneratorService)
    gen = WorkPackages::DefaultQueryGeneratorService
    unless defined?(CovenantAssignedToMeNoStatus)
      Object.const_set(:CovenantAssignedToMeNoStatus, Module.new do
        def assigned_to_me_query
          WorkPackages::DefaultQueryGeneratorService::DEFAULT_PARAMS.merge(
            {
              c: %w[id subject type status author updatedAt],
              f: [{ "n" => "assigneeOrGroup", "o" => "=", "v" => ["me"] }]
            }
          )
        end
      end)
    end
    unless gen.singleton_class.ancestors.include?(CovenantAssignedToMeNoStatus)
      gen.singleton_class.prepend(CovenantAssignedToMeNoStatus)
    end
  end

  Rails.logger.info("[covenant] WP default filters cleared (show all)")
rescue StandardError => e
  Rails.logger.warn("[covenant] no default WP filters failed: #{e.class}: #{e.message}")
end

def covenant_patch_work_package_queries!
  return unless defined?(WorkPackages::Menu)

  WorkPackages::Menu.class_eval do
    def default_queries
      query_generator = WorkPackages::DefaultQueryGeneratorService.new(with_project: project)
      %i[all_open assigned_to_me].filter_map do |query_key|
        params = query_generator.call(query_key:)
        next if params.nil?

        title =
          if query_key == :all_open
            I18n.t("label_work_package_view_all", default: "Все задания")
          else
            I18n.t("js.work_packages.default_queries.#{query_key}")
          end

        menu_item(
          title:,
          query_params: params,
          show_enterprise_icon: false
        )
      end
    end
  end

  Rails.logger.info("[covenant] WP sidebar queries: all + assigned_to_me")
rescue StandardError => e
  Rails.logger.warn("[covenant] WP queries patch failed: #{e.class}: #{e.message}")
end

def covenant_rename_work_packages_to_assignments!
  I18n.backend.store_translations(
    :ru,
    label_home: "Предприятия",
    label_project: "Предприятие",
    label_project_plural: "Предприятия",
    label_projects_menu: "Предприятия",
    label_project_new: "Новое предприятие",
    label_project_view_all: "Все предприятия",
    label_covenant_folders: "Папки",
    notice_account_invalid_credentials: "Неверный логин или пароль.",
    notice_account_invalid_credentials_or_blocked: "Неверный логин или пароль. Если ошибка повторяется, подождите пару минут и попробуйте снова.",
    notice_account_wrong_password: "Неверный пароль.",
    notice_covenant_no_enterprises: "Нет доступных предприятий. Обратитесь к администратору.",
    label_project_settings: "Настройки предприятия",
    label_work_package: "Ковенанта",
    label_work_package_plural: "Ковенанты",
    label_work_package_new: "Создать",
    label_work_package_edit: "Редактирование ковенанты %{name}",
    label_work_package_view_all: "Все ковенанты",
    label_work_package_tracking: "Отслеживание ковенант",
    label_work_package_types: "Типы ковенант",
    label_work_package_status: "Статус ковенанты",
    label_work_package_status_plural: "Статусы ковенант",
    label_work_package_attachments: "Вложения ковенанты",
    label_work_package_comments: "Комментарии к ковенанте",
    label_work_package_hierarchy: "Иерархия ковенант",
    label_work_package_category_plural: "Категории ковенант",
    label_all_open_wps: "Все ковенанты",
    label_activity: "История изменений",
    label_project_activity: "История изменений",
    project_module_activity: "История изменений",
    label_my_activity: "Моя история изменений",
    button_all_filters: "Все фильтры",
    button_filter: "Фильтр",
    label_change_password: "Сменить пароль",
    label_zen_mode: "Режим на весь экран",
    label_past: "Прошлое",
    projects: {
      lists: {
        active: "Все предприятия",
        my: "Мои предприятия",
        favorited: "Избранное",
        archived: "Архив"
      }
    },
    header: {
      project_select_component: {
        all_projects: "Предприятия",
        favorites: "Избранное",
        leave_project: "Покинуть предприятие",
        title: "Предприятия"
      }
    },
    activerecord: {
      attributes: {
        project: {
          id: "ID",
          identifier: "Идентификатор",
          hierarchy: "Иерархия",
          name: "Имя",
          public: "Общий",
          description: "Описание",
          status_explanation: "Описание статуса"
        }
      }
    },
    js: {
      label_all_projects: "Предприятия",
      label_work_package: "Ковенанта",
      label_work_package_plural: "Ковенанты",
      label_create_work_package: "Создать",
      work_packages: {
        table: {
          configure_button: "Настроить таблицу ковенант",
          summary: "Таблица с названиями ковенант в строках и атрибутами ковенант в столбцах."
        },
        table_configuration: {
          button: "Настроить эту таблицу ковенант",
          modal_title: "Конфигурация таблицы ковенант",
          choose_display_mode: "Отображать ковенанты как"
        },
        create: {
          title: "Создать",
          button: "Создать",
          header_no_type: "Новый запрос (тип ещё не установлен)"
        },
        inline_create: {
          title: "Кликните здесь, чтобы добавить новую ковенанту в этот список"
        },
        no_results: {
          title: "Нет ковенант для показа."
        }
      },
      relation_labels: {
        parent: "Родительская ковенанта",
        child: "Подзадача",
        children: "Подзадачи"
      },
      relations_hierarchy: {
        parent_headline: "Родительская ковенанта",
        children_headline: "Подзадачи"
      },
      relation_buttons: {
        set_parent: "Сделать подзадачей",
        change_parent: "Изменить родительскую ковенанту",
        remove_parent: "Убрать из подзадач",
        add_parent: "Выбрать родительскую ковенанту",
        add_new_child: "Создать подзадачу",
        add_existing_child: "Добавить подзадачу",
        remove_child: "Убрать подзадачу"
      },
      relations_autocomplete: {
        parent_placeholder: "Выберите родительскую ковенанту или Escape для отмены"
      }
    }
  )
  Rails.logger.info("[covenant] renamed WP→Ковенанты, projects→Предприятия")
rescue StandardError => e
  Rails.logger.warn("[covenant] rename WP failed: #{e.class}: #{e.message}")
end

def covenant_show_user_mail!
  return unless defined?(User)
  return if defined?(CovenantUserMailDisplay) && User.ancestors.include?(CovenantUserMailDisplay)

  unless defined?(CovenantUserMailDisplay)
    mail_mod = Module.new
    mail_mod.module_eval do
      def name(formatter = nil)
        mail.presence || super
      end
    end
    Object.const_set(:CovenantUserMailDisplay, mail_mod)
  end

  User.prepend(CovenantUserMailDisplay)
  Rails.logger.info("[covenant] user display -> email")
rescue StandardError => e
  Rails.logger.warn("[covenant] user mail display failed: #{e.class}: #{e.message}")
end

def covenant_register_css_hook!
  return unless defined?(OpenProject::Hook::ViewListener)

  unless defined?(CovenantHideEnterpriseHook)
    Object.const_set(:CovenantHideEnterpriseHook, Class.new(OpenProject::Hook::ViewListener))
  end

  CovenantHideEnterpriseHook.class_eval do
    def covenant_executors_cf_meta
      return "" unless defined?(WorkPackageCustomField)

      cf = WorkPackageCustomField.find_by(name: "Исполнители")
      return "" unless cf

      %(<meta name="covenant-executors-cf" content="customField#{cf.id}">)
    end

    def view_layouts_base_html_head(_context = {})
      <<~HTML.html_safe
        <link rel="stylesheet" href="/covenant-hide-ee.css?v=20260928a" data-covenant="hide-ee">
        <link rel="icon" type="image/png" href="/pulse-favicon.png" data-covenant="favicon">
        <link rel="shortcut icon" href="/pulse-favicon.ico" data-covenant="favicon-ico">
        <link rel="apple-touch-icon" href="/pulse-favicon.png" data-covenant="touch-icon">
        #{covenant_executors_cf_meta}
        <script src="/covenant-ad-invite.js?v=20260930a" defer data-covenant="ad-invite"></script>
      HTML
    end
  end
rescue StandardError => e
  Rails.logger.warn("[covenant] css hook failed: #{e.class}: #{e.message}")
end

# Ставим logo / logo_mobile / favicon через CustomStyle — так OP сам подставляет в .op-logo--*
def covenant_apply_branding!
  return unless defined?(CustomStyle)

  logo = Rails.root.join("custom/images/pulse-logo.png")
  logo = Rails.root.join("public/pulse-logo.png") unless logo.exist?
  fav = Rails.root.join("custom/images/pulse-favicon.png")
  fav = Rails.root.join("public/pulse-favicon.png") unless fav.exist?
  return unless logo.exist?

  style = CustomStyle.current || CustomStyle.new
  need =
    style.new_record? ||
    style.logo_identifier != "pulse-logo.png" ||
    style.logo_mobile_identifier != "pulse-logo.png" ||
    (fav.exist? && style.favicon_identifier != "pulse-favicon.png")

  unless need
    Rails.logger.info("[covenant] branding already applied")
    return
  end

  File.open(logo, "rb") { |f| style.logo = f }
  File.open(logo, "rb") { |f| style.logo_mobile = f }
  File.open(logo, "rb") { |f| style.export_logo = f } if style.respond_to?(:export_logo=)
  if fav.exist?
    File.open(fav, "rb") { |f| style.favicon = f }
    File.open(fav, "rb") { |f| style.touch_icon = f } if style.respond_to?(:touch_icon=)
  end
  style.save!
  RequestStore.clear! if defined?(RequestStore)
  Rails.logger.info("[covenant] branding applied (logo+favicon ПМХ)")
rescue StandardError => e
  Rails.logger.warn("[covenant] branding failed: #{e.class}: #{e.message}")
end

# CustomStyle.logo/favicon в Community без EE не применяются — снимаем гейт.
def covenant_patch_custom_styles_ee!
  return unless defined?(CustomStylesHelper)

  CustomStylesHelper.module_eval do
    def apply_custom_styles?(*)
      CustomStyle.current.present?
    end

    def apply_custom_favicon?
      CustomStyle.current&.favicon.present?
    end

    def apply_custom_touch_icon?
      CustomStyle.current&.touch_icon.present?
    end
  end

  Rails.logger.info("[covenant] custom styles EE gate bypassed")
rescue StandardError => e
  Rails.logger.warn("[covenant] custom styles patch failed: #{e.class}: #{e.message}")
end

# Quick-add: «Новое задание» в предприятии пользователя (не /projects/new)
def covenant_patch_quick_add!
  return unless defined?(Redmine::MenuManager::TopMenu::QuickAddMenu)

  Redmine::MenuManager::TopMenu::QuickAddMenu.module_eval do
    def work_package_quick_add_items
      []
    end

    def covenant_user_enterprise
      user = User.current
      return nil unless user&.logged?

      # В контексте предприятия — создаём здесь
      if in_project_context? && user.allowed_in_project?(:add_work_packages, @project)
        return @project
      end

      allowed = Project.allowed_to(user, :add_work_packages).active
      return nil if allowed.none?

      # «Своё» предприятие: дефолт из ENV, если пользователь туда может писать; иначе первое доступное
      ident = ENV.fetch("COVENANT_DEFAULT_ENTERPRISE", "pao-koks")
      preferred = allowed.find_by(identifier: ident)
      preferred || allowed.order(:id).first
    end

    def render_quick_add_menu
      return if anonymous_and_login_required?

      project = covenant_user_enterprise
      return unless project

      href = "/projects/#{ERB::Util.url_encode(project.identifier)}/work_packages/details/new"
      label = I18n.t(:label_work_package_new)

      render(
        Primer::Beta::Button.new(
          tag: :a,
          href:,
          scheme: :primary,
          classes: "op-app-header--primer-button",
          test_selector: "quick-add-menu-button",
          "aria-label": label
        )
      ) do |button|
        button.with_leading_visual_icon(icon: :plus)
        label
      end
    end
  end

  Rails.logger.info("[covenant] quick-add → new work package in user enterprise")
rescue StandardError => e
  Rails.logger.warn("[covenant] quick-add patch failed: #{e.class}: #{e.message}")
end

# /projects: кнопка «Добавить» без portfolio/program — только предприятие
def covenant_patch_projects_create_button!
  return unless defined?(Projects::IndexSubHeaderComponent)

  Projects::IndexSubHeaderComponent.class_eval do
    def allowed_new_workspace_types
      @allowed_new_workspace_types ||= [].tap do |types|
        types << "project" if @current_user.allowed_globally?(:add_project)
      end
    end
  end

  Rails.logger.info("[covenant] projects create → only enterprise")
rescue StandardError => e
  Rails.logger.warn("[covenant] projects create patch failed: #{e.class}: #{e.message}")
end

# Мастер нового предприятия: без шаблона, один экран, «Завод AD» с родителя.
def covenant_patch_project_create_wizard!
  if defined?(ProjectsController)
    unless defined?(CovenantProjectCreateWizard) &&
           ProjectsController.ancestors.include?(CovenantProjectCreateWizard)
      unless defined?(CovenantProjectCreateWizard)
        Object.const_set(:CovenantProjectCreateWizard, Module.new do
          def new_blank
            params[:step] = 2
            @new_project = @parent&.children&.build(params.permit(:workspace_type)) ||
                           Project.new(params.permit(:workspace_type))
            covenant_copy_parent_ad_org!(@new_project, @parent)
            render layout: layout_for_new
          end

          # Одна форма: не прячем ошибки CF (сток чистит их до шага 3).
          def from_step_3?
            true
          end

          def set_wizard_step!(_project)
            params[:step] = 2
          end

          def covenant_copy_parent_ad_org!(project, parent)
            return if project.nil? || parent.nil? || !defined?(ProjectCustomField)

            cf = ProjectCustomField.find_by(name: "Завод AD")
            return unless cf

            raw = parent.custom_value_for(cf)&.value
            return if raw.blank?
            return if project.custom_value_for(cf)&.value.present?

            project.custom_field_values = { cf.id => raw }
          end
        end)
      end
      ProjectsController.prepend(CovenantProjectCreateWizard)
    end
  end

  if defined?(Projects::ProjectCreationFooterComponent)
    Projects::ProjectCreationFooterComponent.class_eval do
      def total_steps
        1
      end
    end
  end

  Rails.logger.info("[covenant] project create wizard: skip template, copy Завод AD from parent")
rescue StandardError => e
  Rails.logger.warn("[covenant] project create wizard patch failed: #{e.class}: #{e.message}")
end

# Бренд в шапке: [лого] Пульс / Система контроля выполнения ковенант
def covenant_patch_logo_wordmark!
  return unless defined?(Redmine::MenuManager::TopMenuHelper)

  Redmine::MenuManager::TopMenuHelper.module_eval do
    def pulse_brand_link(mobile: false)
      extras = mobile ? { class: "pulse-brand pulse-brand_mobile" } : { class: "pulse-brand pulse-brand_desktop" }
      target = mobile ? "mobileLogo" : "desktopLogo"

      link_to(
        configurable_home_url,
        **extras,
        data: { auto_theme_switcher_target: target },
        aria: { label: "Пульс, Система контроля выполнения ковенант" }
      ) do
        safe_join(
          [
            content_tag(:span, "", class: "pulse-brand__mark", "aria-hidden": true),
            content_tag(:span, class: "pulse-brand__text") do
              safe_join(
                [
                  content_tag(:span, "Пульс", class: "pulse-brand__title"),
                  content_tag(:span, "Система контроля выполнения ковенант", class: "pulse-brand__subtitle")
                ]
              )
            end
          ]
        )
      end
    end

    def render_logo
      pulse_brand_link(mobile: false)
    end

    def render_logo_icon
      pulse_brand_link(mobile: true)
    end

    def render_waffle_menu_logo_icon
      content_tag :div, class: "pulse-brand pulse-brand_waffle" do
        safe_join(
          [
            content_tag(:span, "", class: "pulse-brand__mark", "aria-hidden": true),
            content_tag(:span, class: "pulse-brand__text") do
              safe_join(
                [
                  content_tag(:span, "Пульс", class: "pulse-brand__title"),
                  content_tag(:span, "Система контроля выполнения ковенант", class: "pulse-brand__subtitle")
                ]
              )
            end
          ]
        )
      end
    end
  end

  Rails.logger.info("[covenant] logo brand lockup «Пульс»")
rescue StandardError => e
  Rails.logger.warn("[covenant] logo wordmark patch failed: #{e.class}: #{e.message}")
end

def covenant_strip_share_permissions!
  return unless defined?(Role)

  share_perms = %i[share_work_packages view_shared_work_packages]
  Role.find_each do |role|
    perms = role.permissions.map(&:to_sym)
    cleaned = perms - share_perms
    next if cleaned.size == perms.size

    role.permissions = cleaned
    role.save(validate: false)
  end
rescue StandardError => e
  Rails.logger.warn("[covenant] failed to strip share permissions: #{e.message}")
end

def covenant_disable_extra_modules!
  return unless defined?(Project)

  drop = %w[
    documents wiki repository forums news calendar meetings
    board_view team_planner gantt budgets costs
  ]
  Project.find_each do |project|
    mods = project.enabled_module_names - drop
    next if mods.size == project.enabled_module_names.size

    project.enabled_module_names = mods
    project.save(validate: false)
  end
rescue StandardError => e
  Rails.logger.warn("[covenant] disable extra modules failed: #{e.message}")
end

# Контекстное меню / карточка: без PDF/Atom (подзадачи оставляем).
def covenant_strip_wp_export_and_child_actions!
  if defined?(API::V3::WorkPackages::WorkPackageRepresenter)
    unless defined?(CovenantWpExportStrip) &&
           API::V3::WorkPackages::WorkPackageRepresenter.ancestors.include?(CovenantWpExportStrip)
      unless defined?(CovenantWpExportStrip)
        Object.const_set(:CovenantWpExportStrip, Module.new do
          def export_work_packages_allowed?
            false
          end
        end)
      end
      API::V3::WorkPackages::WorkPackageRepresenter.prepend(CovenantWpExportStrip)
    end
  end

  if defined?(API::V3::WorkPackages::WorkPackageCollectionRepresenter)
    API::V3::WorkPackages::WorkPackageCollectionRepresenter.class_eval do
      def representation_format_atom
        nil
      end
    end
  end

  if defined?(Setting) && Setting.respond_to?(:feeds_enabled=)
    Setting.feeds_enabled = false
  end

  covenant_patch_wp_context_menu_js!

  Rails.logger.info("[covenant] WP actions stripped: pdf/atom (subtasks kept)")
rescue StandardError => e
  Rails.logger.warn("[covenant] strip WP actions failed: #{e.class}: #{e.message}")
end

def covenant_patch_wp_context_menu_js!
  Dir[Rails.root.join("public/assets/frontend/chunk-*.js")].each do |path|
    marker = "#{path}.covenant-wp-menu"
    next if File.exist?(marker)

    raw = File.read(path)
    next unless raw.include?("PERMITTED_CONTEXT_MENU_ACTIONS") && raw.include?("generate_pdf")

    patched = raw.dup
    patched.gsub!(/\{\s*key:\s*"generate_pdf",[\s\S]*?\},?\s*/, "")
    patched.gsub!(/\{\s*key:\s*"export-atom",[\s\S]*?\},?\s*/, "")
    # addChild / подзадачи — не трогаем

    next if patched == raw

    File.write(path, patched)
    File.write(marker, "patched\n")
    Rails.logger.info("[covenant] patched WP context menu JS #{File.basename(path)}")
  end
rescue StandardError => e
  Rails.logger.warn("[covenant] WP context menu JS patch failed: #{e.class}: #{e.message}")
end

Rails.application.config.to_prepare do
  covenant_patch_help_menu!
  covenant_patch_module_menu!
  covenant_patch_custom_styles_ee!
  covenant_patch_logo_wordmark!
  covenant_patch_quick_add!
  covenant_patch_projects_create_button!
  covenant_patch_project_create_wizard!
  covenant_remove_menus!
  covenant_strip_project_status_sidebar!
  covenant_localize_project_phases!
  covenant_strip_project_list_columns!
  covenant_disable_wikis!
  covenant_no_default_wp_filters!
  covenant_patch_work_package_queries!
  covenant_rename_work_packages_to_assignments!
  covenant_show_user_mail!
  covenant_redirect_home!
  covenant_redirect_project_to_work_packages!
  covenant_redirect_root_wp_to_folders!
  covenant_project_list_roots_only!
  covenant_hide_my_page!
  covenant_redirect_naked_header_projects!
  covenant_strip_my_account!
  covenant_force_letter_avatars!
  covenant_strip_wp_export_and_child_actions!
  covenant_localize_dismiss!
  covenant_disable_self_service_auth!
  covenant_patch_wp_copy_dates!
end

Rails.application.config.after_initialize do
  locale_file = Rails.root.join("config/locales/zzz_covenant.ru.yml")
  if locale_file.exist?
    path = locale_file.to_s
    I18n.load_path.delete(path)
    I18n.load_path << path
    I18n.reload!
  end

  covenant_patch_frontend_locale!
  covenant_patch_help_menu!
  covenant_patch_module_menu!
  covenant_patch_custom_styles_ee!
  covenant_patch_logo_wordmark!
  covenant_patch_quick_add!
  covenant_patch_projects_create_button!
  covenant_patch_project_create_wizard!
  covenant_remove_menus!
  covenant_strip_project_status_sidebar!
  covenant_localize_project_phases!
  covenant_strip_project_list_columns!
  covenant_disable_wikis!
  covenant_no_default_wp_filters!
  covenant_patch_work_package_queries!
  covenant_rename_work_packages_to_assignments!
  covenant_show_user_mail!
  covenant_redirect_home!
  covenant_redirect_project_to_work_packages!
  covenant_redirect_root_wp_to_folders!
  covenant_project_list_roots_only!
  covenant_hide_my_page!
  covenant_redirect_naked_header_projects!
  covenant_strip_my_account!
  covenant_force_letter_avatars!
  covenant_strip_wp_export_and_child_actions!
  covenant_localize_dismiss!
  covenant_register_css_hook!
  covenant_apply_branding!
  covenant_strip_share_permissions!
  covenant_disable_extra_modules!
  covenant_set_landing_urls!
  covenant_disable_self_service_auth!
  covenant_set_default_wp_columns!
  covenant_fix_priorities!
  covenant_purge_extra_statuses!
  covenant_patch_wp_copy_dates!
  covenant_reload_mailer_settings!
end

# Фронт на каждой карточке ковенанты делает GET /api/v3/shares.
# Шаринг выпилен (нет view_shared_work_packages) → OP отвечает 404 в консоль.
# Отдаём пустую коллекцию 200, UI шаринга по-прежнему скрыт CSS.
unless defined?(CovenantSharesEmptyRack)
  Object.const_set(:CovenantSharesEmptyRack, Class.new do
    def initialize(app)
      @app = app
    end

    def call(env)
      if env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/api/v3/shares"
        href = env["PATH_INFO"]
        qs = env["QUERY_STRING"]
        href = "#{href}?#{qs}" if qs.present?
        body = {
          "_type" => "Collection",
          "total" => 0,
          "count" => 0,
          "pageSize" => 0,
          "offset" => 1,
          "_embedded" => { "elements" => [] },
          "_links" => { "self" => { "href" => href } }
        }.to_json
        return [200, { "Content-Type" => "application/hal+json; charset=utf-8" }, [body]]
      end

      @app.call(env)
    end
  end)

  Rails.application.config.middleware.use(CovenantSharesEmptyRack)
end
