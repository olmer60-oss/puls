# frozen_string_literal: true

# Личные фильтры таблицы ковенант (пользователь × предприятие).
# Сток OP: «Применить» только текущий вид/URL, дефолт «Все» не пишется.
# Сайдбар представлений убран (wp-query-menu) — Save as негде жить.
# Храним в user.pref (без permission save_queries). Restore на Query.new_default.

module CovenantPersonalQuery
  PREF_KEY = "covenant_wp_query"
  SAVE_KEYS = %w[
    filters column_names columns sort_criteria sort_by group_by
    show_hierarchies display_sums include_subprojects
  ].freeze

  class << self
    def restore_into(query, user)
      return false unless query.instance_of?(::Query) && query.project && user&.logged?

      payload = payload_for(user, query.project_id)
      return false if payload.blank?

      apply_payload(query, payload)
      true
    rescue StandardError => e
      Rails.logger.warn("[covenant-query] restore failed: #{e.class}: #{e.message}")
      false
    end

    def save_from!(query, user)
      return unless query.instance_of?(::Query) && query.project && user&.logged?

      store(user, query.project_id, dump(query))
    rescue StandardError => e
      Rails.logger.warn("[covenant-query] save failed: #{e.class}: #{e.message}")
    end

    def user_query_params?(params)
      return false unless params.respond_to?(:keys)

      params.keys.any? { |k| SAVE_KEYS.include?(k.to_s) }
    end

    def payload_for(user, project_id)
      raw = user.pref[PREF_KEY]
      return unless raw.is_a?(Hash)

      raw.stringify_keys[project_id.to_s]
    end

    def store(user, project_id, payload)
      pref = user.pref
      all = pref[PREF_KEY]
      all = all.is_a?(Hash) ? all.stringify_keys : {}
      key = project_id.to_s
      return if all[key] == payload

      merged = all.merge(key => payload)
      if pref.respond_to?(:others=)
        others = pref.others.is_a?(Hash) ? pref.others.stringify_keys : {}
        pref.others = others.merge(PREF_KEY => merged)
      else
        pref[PREF_KEY] = merged
      end
      pref.others_will_change! if pref.respond_to?(:others_will_change!)
      saved = pref.save
      Rails.logger.info(
        "[covenant-query] #{saved ? "saved" : "save-failed"} user=#{user.login} project=#{project_id} " \
        "filters=#{Array(payload['f']).size}"
      )
    end

    def dump(query)
      {
        "f" => query.filters.map { |f| dump_filter(f) }.compact,
        "c" => Array(query.column_names).map(&:to_s),
        "s" => Array(query.sort_criteria),
        "g" => query.group_by.to_s.presence,
        "h" => query.show_hierarchies,
        "sums" => query.display_sums,
        "sub" => query.include_subprojects
      }
    end

    def dump_filter(filter)
      name = filter.respond_to?(:name) ? filter.name : filter.field
      return if name.blank?

      {
        "n" => name.to_s,
        "o" => filter.operator.to_s,
        "v" => Array(filter.values).map { |v| v.respond_to?(:as_json) ? v.as_json : v }
      }
    end

    def apply_payload(query, payload)
      payload = payload.stringify_keys
      query.filters = []
      Array(payload["f"]).each do |raw|
        f = raw.stringify_keys
        query.add_filter(f["n"], f["o"], Array(f["v"]))
      rescue StandardError => e
        Rails.logger.warn("[covenant-query] skip filter #{raw.inspect}: #{e.message}")
      end

      cols = Array(payload["c"]).map(&:to_sym)
      query.column_names = cols if cols.any?
      if payload["s"].present?
        query.sort_criteria = payload["s"]
      else
        query.set_default_sort
      end
      query.group_by = payload["g"]
      query.show_hierarchies = payload["h"] unless payload["h"].nil?
      query.display_sums = payload["sums"] unless payload["sums"].nil?
      query.include_subprojects = payload["sub"] unless payload["sub"].nil?
    end
  end
end

def covenant_patch_personal_wp_query!
  return unless defined?(Query)

  unless defined?(CovenantQueryNewDefault)
    Object.const_set(:CovenantQueryNewDefault, Module.new do
      def new_default(attributes = nil)
        query = super
        query.show_hierarchies = true
        CovenantPersonalQuery.restore_into(query, User.current)
        query
      end
    end)
  end
  unless Query.singleton_class.ancestors.include?(CovenantQueryNewDefault)
    Query.singleton_class.prepend(CovenantQueryNewDefault)
  end

  return unless defined?(Queries::SetAttributesService)

  unless defined?(CovenantQueryPersistOnSet)
    Object.const_set(:CovenantQueryPersistOnSet, Module.new do
      def call(params)
        result = super
        covenant_persist_personal_query(result, params)
        result
      end

      def covenant_persist_personal_query(result, params)
        return unless result.respond_to?(:success?) && result.success?

        query = result.result
        return unless query.instance_of?(::Query)
        return if query.persisted? || query.project.nil?
        return unless CovenantPersonalQuery.user_query_params?(params)

        CovenantPersonalQuery.save_from!(query, user)
      end
    end)
  end
  unless Queries::SetAttributesService.ancestors.include?(CovenantQueryPersistOnSet)
    Queries::SetAttributesService.prepend(CovenantQueryPersistOnSet)
  end

  Rails.logger.info("[covenant-query] personal WP filters (user.pref #{CovenantPersonalQuery::PREF_KEY})")
rescue StandardError => e
  Rails.logger.warn("[covenant-query] patch failed: #{e.class}: #{e.message}")
end

Rails.application.config.to_prepare do
  covenant_patch_personal_wp_query!
end

Rails.application.config.after_initialize do
  covenant_patch_personal_wp_query!
end
