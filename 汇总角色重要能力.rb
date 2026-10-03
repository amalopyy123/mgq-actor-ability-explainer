# encoding: UTF-8

# Build a compact, reader-oriented CSV from actor_important_abilities.csv.
# This script does not parse game data or rewrite translations.

require 'csv'
require 'fileutils'

module ActorImportantAbilitySummarizer
  INPUT_PATH = File.expand_path('导出CSV/actor_important_abilities.csv', __dir__)
  OUTPUT_PATH = File.expand_path('导出CSV/actor_capability_summary.csv', __dir__)
  OUTPUT_HEADERS = %w[
    actor_id actor_name group description_chinese source_raw comment_chinese
    category record_count ability_orders
  ].freeze

  GROUP_NAMES = {
    'skill' => '技能使用权限',
    'equipment' => '可装备',
    'resistance' => '属性或状态抗性',
    'attribute' => '属性效果',
    'skill_chain' => '技能链',
    'skill_boost' => '技能强化',
    'cost' => '技能消耗',
    'stat_change' => '能力值计算',
    'parameter' => '基础参数',
    'attack' => '攻击效果',
    'trigger' => '触发效果',
    'action' => '行动次数',
    'trait' => '其他特性',
    'special' => '其他',
    'missing_source_raw' => '缺少来源说明',
    'unclassified' => '其他'
  }.freeze

  class Builder
    def initialize(input_path, output_path)
      @input_path = input_path
      @output_path = output_path
    end

    def run
      rows = CSV.read(@input_path, headers: true, encoding: 'UTF-8', liberal_parsing: true)
      output_rows = []
      rows.group_by { |row| field(row, 'actor_id', 0) }.each_value do |actor_rows|
        append_actor_rows(actor_rows, output_rows)
      end

      FileUtils.mkdir_p(File.dirname(@output_path))
      CSV.open(@output_path, 'wb', write_headers: true, headers: OUTPUT_HEADERS,
               encoding: 'UTF-8') do |csv|
        output_rows.each { |row| csv << OUTPUT_HEADERS.map { |header| row[header] } }
      end

      puts "Exported actor capability summary to #{@output_path}"
      puts "Summary records: #{output_rows.length}"
    end

    private

    def append_actor_rows(actor_rows, output_rows)
      merge_slots = {}

      actor_rows.each do |row|
        next if skipped_row?(row)

        # Comments describe a specific source record and therefore block merging.
        if non_empty?(row['comment_chinese'])
          output_rows << standalone_row(row)
          next
        end

        candidate = merge_candidate(row)
        unless candidate
          output_rows << standalone_row(row)
          next
        end

        slot_key = [row['category'], candidate[:key]]
        existing = merge_slots[slot_key]
        if existing
          merge_row!(existing, row, candidate)
        else
          summary = standalone_row(row)
          summary['description_chinese'] = candidate[:description]
          summary['group'] = candidate[:group]
          merge_slots[slot_key] = summary
          output_rows << summary
        end
      end
    end

    def skipped_row?(row)
      row['importance'].to_s == 'skipped' ||
        (empty?(row['description_chinese']) && empty?(row['comment_chinese']))
    end

    def standalone_row(row)
      {
        'actor_id' => field(row, 'actor_id', 0),
        'actor_name' => row['actor_name'],
        'group' => group_name(row),
        'description_chinese' => normalized_description(row),
        'source_raw' => row['source_raw'],
        'comment_chinese' => row['comment_chinese'],
        'category' => row['category'],
        'record_count' => '1',
        'ability_orders' => row['ability_order']
      }
    end

    def normalized_description(row)
      description = row['description_chinese'].to_s
      return description unless row['category'].to_s == 'skill_boost'

      source_raw = row['source_raw'].to_s
      type_boost = source_raw.match?(/<窮地スキルタイプ強化(?:\s|>)/) ||
                   source_raw.match?(/<スキルタイプ強化(?:\s|>)/)
      return description unless type_boost

      description.sub(/\A(濒死时.+?|.+?)威力( \+.+%\z)/) do
        "#{$1}强化#{$2}"
      end
    end

    def merge_row!(summary, row, candidate)
      summary['description_chinese'] = candidate[:description_for_merge].call(
        summary['description_chinese'], row['description_chinese']
      )
      summary['source_raw'] = join_values(summary['source_raw'], row['source_raw'])
      summary['record_count'] = summary['record_count'].to_i + 1
      summary['ability_orders'] = join_values(summary['ability_orders'], row['ability_order'])
    end

    def merge_candidate(row)
      description = row['description_chinese'].to_s.strip
      category = row['category'].to_s

      if category == 'skill' && (match = description.match(/\A可以使用(.+)\z/))
        return list_candidate('技能使用权限', '可以使用', match[1], 'skill_permission')
      end

      if category == 'skill' && (match = description.match(/\A习得(.+)\z/))
        return list_candidate('固有习得', '习得', match[1], 'learned_skill')
      end

      if category == 'equipment' && (match = description.match(/\A可以装备(.+)\z/))
        return list_candidate('可装备', '可以装备', match[1], 'equipment_permission')
      end

      if category == 'resistance'
        damage_multiplier = description.match(/\A受到(.+?)属性伤害变为(×.+)\z/)
        return element_damage_multiplier_candidate(damage_multiplier[1], damage_multiplier[2]) if damage_multiplier

        state = description.match(/\A免疫(.+?)状态（(.+)）\z/)
        return list_candidate('状态免疫', '免疫', state[1], "state_immunity:#{state[2]}",
                              '状态', state[2]) if state

        state_rate = description.match(/\A被施加(.+?)状态的概率变为(×.+)\z/)
        return state_rate_candidate(state_rate[1], state_rate[2]) if state_rate

        element = description.match(/\A免疫(.+?)属性伤害（(.+)）\z/)
        return list_candidate('属性抗性', '免疫', element[1], "element_immunity:#{element[2]}",
                              '属性伤害', element[2]) if element
      end

      if category == 'attribute'
        penetration_parts = extract_attribute_penetration_pairs(description)
        return attribute_penetration_candidate(penetration_parts) if penetration_parts

        reflection_parts = extract_attribute_reflection_pairs(description)
        return attribute_reflection_candidate(reflection_parts) if reflection_parts

        added = description.match(/\A(.+?附加)(.+?)属性\z/)
        return list_candidate('属性追加', added[1], added[2], "attribute_add:#{added[1]}",
                              '属性') if added

        absorbed_parts = extract_absorb_pairs(description)
        return attribute_absorb_candidate(absorbed_parts) if absorbed_parts
      end

      if category == 'special'
        evasion = description.match(/\A(.*闪避率) \+(.+)\z/)
        return evasion_rate_candidate(evasion[1], evasion[2]) if evasion
      end

      if category == 'skill_boost'
        trigger = description.match(/\A(.+?)(速攻发动|顽强发动)\z/)
        return skill_trigger_candidate(trigger[1], trigger[2]) if trigger

        full_resource = description.match(/\A(.+?)满(HP|MP|SP)时威力 \+(.+)%\z/)
        return full_resource_power_candidate(full_resource[1], full_resource[2], full_resource[3]) if full_resource

        near_death = description.match(/\A濒死时(.+?)(?:强化|威力) \+(.+)%\z/)
        if near_death && row['source_raw'].to_s.match?(/<窮地スキルタイプ強化(?:\s|>)/)
          return near_death_skill_candidate(near_death[1], near_death[2])
        end

        skill_attribute_parts = extract_skill_attribute_addition_parts(description)
        return skill_attribute_addition_candidate(skill_attribute_parts) if skill_attribute_parts
      end

      if category == 'attack'
        normal_attack = description.match(/\A普通攻击及采用普通攻击属性的技能附加(.+?)属性\z/)
        return normal_attack_attribute_candidate(normal_attack[1]) if normal_attack

        status_add = description.match(/\A攻击时附加(.+?)（基础附加率(.+?)）\z/)
        return attack_status_candidate(status_add[1], status_add[2]) if status_add
      end

      if category == 'cost'
        cost = description.match(/\A(.+?)(HP|MP|SP)消耗量(变为.+)\z/)
        if cost
          return cost_candidate(cost[1].sub(/的\z/, ''), cost[2], cost[3])
        end
      end

      if category == 'parameter'
        parameter = description.match(/\A基础(.+?)变为(×.+)\z/)
        return base_parameter_candidate(parameter[1], parameter[2]) if parameter
      end

      if category == 'stat_change'
        replacement = description.match(/\A(.+?)计算(.+?)时，取(.+?)与(.+?)中的较高值\z/)
        return stat_replacement_candidate(replacement[1], replacement[2], replacement[3], replacement[4]) if replacement

        additive = description.match(/\A(.+?)计算(.+?)时，额外加上(.+?)的(.+)\z/)
        return stat_additive_candidate(additive[1], additive[2], additive[3], additive[4]) if additive
      end

      if category == 'special'
        trigger_state = description.match(/\A(HP(?:低于|达到).+?时)(获得|解除)「(.+)」效果\z/)
        return trigger_state_candidate(trigger_state[1], trigger_state[2], trigger_state[3]) if trigger_state
      end

      nil
    end

    def list_candidate(group, prefix, item, key, suffix = '', suffix_value = nil)
      {
        key: key,
        group: group,
        description: format_list(prefix, item, suffix, suffix_value),
        description_for_merge: lambda do |left, right|
          merge_list_descriptions(prefix, left, right, suffix, suffix_value)
        end
      }
    end

    def cost_candidate(target, cost_type, phrase)
      suffix = "#{cost_type}消耗量#{phrase}"
      {
        key: "cost:#{cost_type}:#{phrase}",
        group: '技能消耗',
        description: "#{target}#{suffix}",
        description_for_merge: lambda do |left, right|
          left_target = extract_cost_target(left, cost_type, phrase)
          right_target = extract_cost_target(right, cost_type, phrase)
          "#{(left_target.split('、') + right_target.split('、')).map(&:strip).reject(&:empty?).uniq.join('、')}#{suffix}"
        end
      }
    end

    def base_parameter_candidate(name, phrase)
      {
        key: "base_parameter:#{phrase}",
        group: '基础参数',
        description: "基础#{name}变为#{phrase}",
        description_for_merge: lambda do |left, right|
          left_name = extract_base_parameter_name(left, phrase)
          right_name = extract_base_parameter_name(right, phrase)
          names = (left_name.split('、') + right_name.split('、')).map(&:strip).reject(&:empty?).uniq
          "基础#{names.join('、')}变为#{phrase}"
        end
      }
    end

    def attribute_absorb_candidate(pairs)
      {
        key: 'attribute_absorb',
        group: '属性吸收',
        description: format_absorb_description(pairs),
        description_for_merge: lambda do |left, right|
          merged_pairs = (extract_absorb_pairs(left) + extract_absorb_pairs(right)).uniq
          format_absorb_description(merged_pairs)
        end
      }
    end

    def attribute_penetration_candidate(pairs)
      {
        key: 'attribute_penetration',
        group: '属性穿透',
        description: format_attribute_penetration_description(pairs),
        description_for_merge: lambda do |left, right|
          merged_pairs = (extract_attribute_penetration_pairs(left) + extract_attribute_penetration_pairs(right)).uniq
          format_attribute_penetration_description(merged_pairs)
        end
      }
    end

    def attribute_reflection_candidate(pairs)
      {
        key: 'attribute_reflection',
        group: '属性反射',
        description: format_attribute_reflection_description(pairs),
        description_for_merge: lambda do |left, right|
          merged_pairs = (extract_attribute_reflection_pairs(left) + extract_attribute_reflection_pairs(right)).uniq
          format_attribute_reflection_description(merged_pairs)
        end
      }
    end

    def state_rate_candidate(name, phrase)
      {
        key: "state_application_rate:#{phrase}",
        group: '状态抗性',
        description: "被施加#{name}状态的概率变为#{phrase}",
        description_for_merge: lambda do |left, right|
          left_name = extract_state_rate_target(left, phrase)
          right_name = extract_state_rate_target(right, phrase)
          names = (left_name.split('、') + right_name.split('、')).map(&:strip).reject(&:empty?).uniq
          "被施加#{names.join('、')}状态的概率变为#{phrase}"
        end
      }
    end

    def stat_additive_candidate(skill, target, amount, source)
      {
        key: "stat_additive:#{skill}:#{amount}:#{source}",
        group: '能力值计算',
        description: "#{skill}计算#{target}时，额外加上#{amount}的#{source}",
        description_for_merge: lambda do |left, right|
          left_target = extract_stat_additive_target(left, skill, amount, source)
          right_target = extract_stat_additive_target(right, skill, amount, source)
          targets = (left_target.split('、') + right_target.split('、')).map(&:strip).reject(&:empty?).uniq
          "#{skill}计算#{targets.join('、')}时，额外加上#{amount}的#{source}"
        end
      }
    end

    def stat_replacement_candidate(skill_names, target, source, replacement)
      {
        key: "stat_replacement:#{target}:#{source}:#{replacement}",
        group: '能力值计算',
        description: "#{skill_names}计算#{target}时，取#{source}与#{replacement}中的较高值",
        description_for_merge: lambda do |left, right|
          left_names = extract_stat_replacement_skills(left, target, source, replacement)
          right_names = extract_stat_replacement_skills(right, target, source, replacement)
          names = (left_names + right_names).map(&:strip).reject(&:empty?).uniq
          "#{names.join('、')}计算#{target}时，取#{source}与#{replacement}中的较高值"
        end
      }
    end

    def evasion_rate_candidate(name, value)
      {
        key: "evasion_rate:#{value}",
        group: '其他',
        description: "#{name} +#{value}",
        description_for_merge: lambda do |left, right|
          left_names = extract_evasion_names(left, value)
          right_names = extract_evasion_names(right, value)
          names = (left_names + right_names).map(&:strip).reject(&:empty?).uniq
          "#{names.join('、')}均 +#{value}"
        end
      }
    end

    def skill_trigger_candidate(skill_names, trigger)
      {
        key: "skill_trigger:#{trigger}",
        group: '技能强化',
        description: "#{skill_names}#{trigger}",
        description_for_merge: lambda do |left, right|
          left_names = extract_skill_trigger_names(left, trigger)
          right_names = extract_skill_trigger_names(right, trigger)
          names = (left_names + right_names).map(&:strip).reject(&:empty?).uniq
          "#{names.join('、')}#{trigger}"
        end
      }
    end

    def full_resource_power_candidate(skill_names, resource, amount)
      {
        key: "full_resource_power:#{resource}:#{amount}",
        group: '技能强化',
        description: "#{skill_names}满#{resource}时威力 +#{amount}%",
        description_for_merge: lambda do |left, right|
          left_names = extract_full_resource_names(left, resource, amount)
          right_names = extract_full_resource_names(right, resource, amount)
          names = (left_names + right_names).map(&:strip).reject(&:empty?).uniq
          "#{names.join('、')}满#{resource}时威力 +#{amount}%"
        end
      }
    end

    def near_death_skill_candidate(skill_names, amount)
      {
        key: "near_death_skill_boost:#{amount}",
        group: '技能强化',
        description: "濒死时#{skill_names}强化 +#{amount}%",
        description_for_merge: lambda do |left, right|
          left_names = extract_near_death_names(left, amount)
          right_names = extract_near_death_names(right, amount)
          names = (left_names + right_names).map(&:strip).reject(&:empty?).uniq
          "濒死时#{names.join('、')}强化 +#{amount}%"
        end
      }
    end

    def skill_attribute_addition_candidate(parts)
      target = parts.first.last
      {
        key: "skill_attribute_addition:#{target}",
        group: '属性追加',
        description: format_skill_attribute_addition_description(parts),
        description_for_merge: lambda do |left, right|
          merged_parts = extract_skill_attribute_addition_parts(left) + extract_skill_attribute_addition_parts(right)
          format_skill_attribute_addition_description(merged_parts.uniq)
        end
      }
    end

    def trigger_state_candidate(condition, action, state_name)
      {
        key: "trigger_state:#{condition}:#{action}",
        group: '触发效果',
        description: format_trigger_state_description(condition, action, [state_name]),
        description_for_merge: lambda do |left, right|
          left_state = extract_trigger_state_name(left, condition, action)
          right_state = extract_trigger_state_name(right, condition, action)
          states = (left_state + right_state).map(&:strip).reject(&:empty?).uniq
          format_trigger_state_description(condition, action, states)
        end
      }
    end

    def element_damage_multiplier_candidate(name, phrase)
      suffix = "属性伤害变为#{phrase}"
      {
        key: "element_damage_multiplier:#{phrase}",
        group: '属性抗性',
        description: "受到#{name}#{suffix}",
        description_for_merge: lambda do |left, right|
          left_name = extract_element_damage_target(left, phrase)
          right_name = extract_element_damage_target(right, phrase)
          names = (left_name.split('、') + right_name.split('、')).map(&:strip).reject(&:empty?).uniq
          "受到#{names.join('、')}#{suffix}"
        end
      }
    end

    def normal_attack_attribute_candidate(name)
      {
        key: 'normal_attack_attribute_add',
        group: '攻击效果',
        description: "普通攻击及采用普通攻击属性的技能附加#{name}属性",
        description_for_merge: lambda do |left, right|
          left_name = extract_normal_attack_attribute(left)
          right_name = extract_normal_attack_attribute(right)
          names = (left_name.split('、') + right_name.split('、')).map(&:strip).reject(&:empty?).uniq
          "普通攻击及采用普通攻击属性的技能附加#{names.join('、')}属性"
        end
      }
    end

    def attack_status_candidate(name, rate)
      {
        key: "attack_status_add:#{rate}",
        group: '攻击效果',
        description: "攻击时附加#{name}（基础附加率#{rate}）",
        description_for_merge: lambda do |left, right|
          left_name = extract_attack_status_target(left, rate)
          right_name = extract_attack_status_target(right, rate)
          names = (left_name.split('、') + right_name.split('、')).map(&:strip).reject(&:empty?).uniq
          "攻击时附加#{names.join('、')}（基础附加率#{rate}）"
        end
      }
    end

    def extract_normal_attack_attribute(description)
      match = description.match(/\A普通攻击及采用普通攻击属性的技能附加(.+?)属性\z/)
      match ? match[1] : description
    end

    def extract_evasion_names(description, value)
      suffix = " +#{value}"
      body = description.to_s.delete_suffix(suffix).delete_suffix('均')
      body.split('、').map(&:strip).reject(&:empty?)
    end

    def extract_skill_trigger_names(description, trigger)
      description.to_s.delete_suffix(trigger).split('、').map(&:strip).reject(&:empty?)
    end

    def extract_full_resource_names(description, resource, amount)
      suffix = "满#{resource}时威力 +#{amount}%"
      description.to_s.delete_suffix(suffix).split('、').map(&:strip).reject(&:empty?)
    end

    def extract_near_death_names(description, amount)
      match = description.to_s.match(/\A濒死时(.+?)(?:强化|威力) \+#{Regexp.escape(amount)}%\z/)
      match ? match[1].split('、').map(&:strip).reject(&:empty?) : [description]
    end

    def extract_skill_attribute_addition_parts(description)
      parts = description.to_s.split('；').map(&:strip).reject(&:empty?)
      pairs = parts.map do |part|
        match = part.match(/\A(.+?)附加(.+?)属性\z/)
        match && [match[1], match[2]]
      end
      return nil unless pairs.all?
      return nil unless pairs.map(&:last).uniq.length == 1

      pairs
    end

    def format_skill_attribute_addition_description(parts)
      target = parts.first.last
      names = parts.flat_map { |skill_names, _| skill_names.split('、') }
      "#{names.map(&:strip).reject(&:empty?).uniq.join('、')}附加#{target}属性"
    end

    def extract_trigger_state_name(description, condition, action)
      prefix = "#{condition}#{action}"
      body = description.to_s.delete_prefix(prefix).delete_suffix('效果')
      body.scan(/「([^」]+)」/).flatten
    end

    def format_trigger_state_description(condition, action, state_names)
      quoted_names = state_names.map { |name| "「#{name}」" }.join('、')
      "#{condition}#{action}#{quoted_names}效果"
    end

    def extract_attack_status_target(description, rate)
      match = description.match(/\A攻击时附加(.+?)（基础附加率#{Regexp.escape(rate)}）\z/)
      match ? match[1] : description
    end

    def extract_state_rate_target(description, phrase)
      match = description.match(/\A被施加(.+?)状态的概率变为#{Regexp.escape(phrase)}\z/)
      match ? match[1] : description
    end

    def extract_stat_additive_target(description, skill, amount, source)
      match = description.match(/\A#{Regexp.escape(skill)}计算(.+?)时，额外加上#{Regexp.escape(amount)}的#{Regexp.escape(source)}\z/)
      match ? match[1] : description
    end

    def extract_stat_replacement_skills(description, target, source, replacement)
      match = description.match(/\A(.+?)计算#{Regexp.escape(target)}时，取#{Regexp.escape(source)}与#{Regexp.escape(replacement)}中的较高值\z/)
      match ? match[1].split('、').map(&:strip).reject(&:empty?) : [description]
    end

    def extract_element_damage_target(description, phrase)
      match = description.match(/\A受到(.+?)属性伤害变为#{Regexp.escape(phrase)}\z/)
      match ? match[1] : description
    end

    def format_absorb_description(pairs)
      names = pairs.map(&:first).join('、')
      ids = pairs.map(&:last).join('、')
      "吸收#{names}属性伤害（属性ID #{ids}）"
    end

    def format_attribute_penetration_description(pairs)
      names = pairs.map(&:first).join('、')
      ids = pairs.map(&:last).join('、')
      "无视#{names}属性抗性（属性ID #{ids}）"
    end

    def format_attribute_reflection_description(pairs)
      names = pairs.map(&:first).join('、')
      ids = pairs.map(&:last).join('、')
      "反射#{names}属性伤害（属性ID #{ids}）"
    end

    def extract_attribute_penetration_pairs(description)
      parts = description.to_s.split(/[；;]/).map(&:strip).reject(&:empty?)
      pairs = parts.map do |part|
        match = part.match(/\A无视(.+?)属性抗性（属性ID (\d+)）\z/)
        match && [match[1], match[2]]
      end
      pairs.all? && pairs
    end

    def extract_attribute_reflection_pairs(description)
      parts = description.to_s.split(/[；;]/).map(&:strip).reject(&:empty?)
      pairs = parts.map do |part|
        match = part.match(/\A反射(.+?)属性伤害（属性ID (\d+)）\z/)
        match && [match[1], match[2]]
      end
      pairs.all? && pairs
    end

    def extract_absorb_pairs(description)
      parts = description.to_s.split('；').map(&:strip).reject(&:empty?)
      pairs = parts.map do |part|
        match = part.match(/\A吸收(.+?)属性伤害（属性ID (\d+)）\z/)
        match && [match[1], match[2]]
      end
      pairs.all? && pairs
    end

    def extract_cost_target(description, cost_type, phrase)
      pattern = /\A(.+?)(?:的)?#{Regexp.escape(cost_type)}消耗量#{Regexp.escape(phrase)}\z/
      match = description.match(pattern)
      match ? match[1] : description
    end

    def extract_base_parameter_name(description, phrase)
      match = description.match(/\A基础(.+?)变为#{Regexp.escape(phrase)}\z/)
      match ? match[1] : description
    end

    def format_list(prefix, item, suffix, suffix_value)
      if suffix.empty?
        "#{prefix}#{item}"
      elsif suffix == '状态'
        "#{prefix}#{item}状态（#{suffix_value}）"
      elsif suffix == '属性伤害' && suffix_value
        "#{prefix}#{item}属性伤害（#{suffix_value}）"
      elsif suffix == '属性伤害'
        "#{prefix}#{item}属性伤害"
      elsif suffix == '属性'
        "#{prefix}#{item}属性"
      else
        "#{prefix}#{item}#{suffix}"
      end
    end

    def merge_list_descriptions(prefix, left, right, suffix, suffix_value)
      left_items = extract_items(prefix, left, suffix, suffix_value)
      right_items = extract_items(prefix, right, suffix, suffix_value)
      items = (left_items + right_items).uniq
      format_list(prefix, items.join('、'), suffix, suffix_value)
    end

    def extract_items(prefix, description, suffix, suffix_value)
      tail = if suffix.empty?
               description.delete_prefix(prefix)
             elsif suffix == '状态'
               description.delete_prefix(prefix).delete_suffix("状态（#{suffix_value}）")
             elsif suffix == '属性伤害' && suffix_value
               description.delete_prefix(prefix).delete_suffix("属性伤害（#{suffix_value}）")
             elsif suffix == '属性伤害'
               description.delete_prefix(prefix).delete_suffix('属性伤害')
             elsif suffix == '属性'
               description.delete_prefix(prefix).delete_suffix('属性')
             else
               description.delete_prefix(prefix).delete_suffix(suffix)
             end
      tail.split('、').map(&:strip).reject(&:empty?)
    end

    def group_name(row)
      category = row['category'].to_s
      description = row['description_chinese'].to_s
      source_raw = row['source_raw'].to_s

      return '触发效果' if description.match?(/\A(?:反击技能|魔法反击技能|必中反击技能|闪避时发动技能)/)
      return '固有习得' if category == 'skill' && row['description_chinese'].to_s.start_with?('习得')

      return '装备特性' if equipment_feature_description?(description) ||
                            source_has_tag?(source_raw, '二刀流') ||
                            source_has_tag?(source_raw, '二刀流強化') ||
                            source_has_tag?(source_raw, '三刀流') ||
                            source_has_tag?(source_raw, '三刀流強化') ||
                            source_has_tag?(source_raw, '両手盾') ||
                            source_has_tag?(source_raw, '両手盾時能力')

      return '连续发动' if source_has_tag?(source_raw, '連続発動タイプ') ||
                            source_has_tag?(source_raw, '連続発動スキル')

      return '属性追加' if source_has_tag?(source_raw, '属性追加') ||
                           source_has_tag?(source_raw, 'スキルタイプ属性追加')
      return '属性吸收' if source_has_tag?(source_raw, '属性吸収')
      return '属性反射' if source_has_tag?(source_raw, '属性反射')
      return '属性穿透' if source_has_tag?(source_raw, '属性貫通')
      return '属性强化' if source_has_tag?(source_raw, '属性強化')

      return '属性抗性' if description.match?(/\A(?:受到.+?属性伤害变为|免疫.+?属性伤害)/)
      return '状态免疫' if description.match?(/\A免疫.+?状态（/)
      return '状态抗性' if description.match?(/\A被施加.+?状态的概率变为/)

      GROUP_NAMES.fetch(category, '其他')
    end

    def equipment_feature_description?(description)
      description.match?(/\A(?:二刀流|三刀流|双手盾)(?:$|时)/)
    end

    def source_has_tag?(source_raw, tag)
      source_raw.match?(/<#{Regexp.escape(tag)}(?:\s|:|>)/)
    end

    def join_values(left, right)
      [left, right].map(&:to_s).reject(&:empty?).join('；')
    end

    def empty?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def non_empty?(value)
      !empty?(value)
    end

    # Ruby's liberal CSV parser can return nil for a malformed first field.
    # Fall back to the positional field so one bad quote cannot merge all actors.
    def field(row, name, index)
      value = row[name]
      empty?(value) ? row.fields[index] : value
    end
  end

  input_path = ARGV[0] || INPUT_PATH
  output_path = ARGV[1] || OUTPUT_PATH
  Builder.new(input_path, output_path).run
end
