# encoding: UTF-8

# Standalone actor note explanation tool.
# It can run outside the game and does not read the large translation JSON.

module RPG
  class BaseItem
    class Feature
    end
  end

  class UsableItem
    class Effect
    end

    class Damage
    end
  end

  class Actor
  end

  class Skill < UsableItem
  end

  class State
  end

  class Enemy
    class Action
    end

    class DropItem
    end
  end

  class BGM
  end

  class ME
  end

  class SE
  end

  class System
    class Terms
    end

    class Vehicle
    end

    class TestBattler
    end
  end
end

class Tone
  def self._load(_data)
    new
  end
end

module GouqiActorPassiveExplainer
  SKIP_TAGS = %w[
    初期サブクラス 経験値曲線 経験済職業 初期装備 初期アビリティ 初期レベル
    TP基本値 TPLv補正 TPLv100補正 性別 カテゴリー ナワバリ 主人格 副人格
    イラスト 固有習得
  ].freeze

  NAME_TRANSLATIONS = {
    'ヒーロー技' => '勇者技',
    '短剣技' => '短剑技', '剣技' => '剑技', '尖剣技' => '尖剑技',
    '刀技' => '刀技', '槍技' => '枪技', '斧技' => '斧技',
    '棍技' => '棍技', '鎌技' => '镰技', '弓技' => '弓技',
    '鞭技' => '鞭技', '投擲技' => '投掷技', '鉄球技' => '铁球技',
    '銃技' => '铳技', '魔法剣' => '魔法剑', '白魔法' => '白魔法',
    '黒魔法' => '黑魔法', '時魔法' => '时魔法', '召喚' => '召唤',
    '忍術' => '忍术', '盗賊技' => '盗贼技', '海賊技' => '海盗技',
    '医術' => '医术', '屍技' => '尸技', '自然感応' => '自然感应',
    'ブレス' => '吐息', '妖術' => '妖术', '格闘技' => '格斗技',
    'マキナ' => '器械', '造技' => '造技',
    '短剣' => '短剑', '剣' => '剑', '尖剣' => '尖剑', '刀' => '刀',
    '槍' => '枪', '斧' => '斧', '棍' => '棍', '鎌' => '镰',
    '弓' => '弓', '鞭' => '鞭', '投擲' => '投掷', '鉄球' => '铁球',
    '銃' => '铳', '杖' => '杖', 'ロッド' => '法杖', '快楽' => '快乐', '炎' => '炎',
    '氷' => '冰', '雷' => '雷', '風' => '风', '土' => '土',
    '水' => '水', '聖' => '圣', '闇' => '暗', '音波' => '音波',
    'バイオ' => '生化', '回復' => '恢复'
  }.freeze

  LABEL_TRANSLATIONS = {
    'TPタイプ消費率' => 'TP消耗率', 'TP消費率' => 'TP消耗率',
    'HP消費率' => 'HP消耗率', 'MP消費率' => 'MP消耗率',
    'ゴールド消費率' => '金币消耗率', '物理ダメージ率' => '物理伤害倍率',
    '魔法ダメージ率' => '魔法伤害倍率', '属性有効度' => '属性抗性倍率',
    '弱体有効度' => '能力下降抗性倍率', 'ステート有効度' => '状态抗性倍率',
    'ダメージアップ' => '伤害提升', '単発スキルダメージアップ' => '单次技能伤害提升',
    '開始時TP' => '开始时TP', '命中率' => '命中率', '回避率' => '闪避率',
    '会心率' => '会心率', '反撃率' => '反击率', '時間停止無視' => '无视时间停止',
    '即死反転' => '即死反转', '二刀流' => '二刀流', '三刀流' => '三刀流',
    '両手盾' => '双手盾', '夢魔' => '梦魔', 'ラーニング' => '学习'
  }.freeze

  PARAM_TRANSLATIONS = {
    '最大HP' => '最大HP', '最大MP' => '最大MP', '攻撃力' => '攻击力',
    '防御力' => '防御力', '魔力' => '魔力', '精神力' => '精神力',
    '素早さ' => '敏捷', '器用さ' => '幸运'
  }.freeze

  def self.explain_actor(actor, lookups = {})
    note = actor.respond_to?(:note) ? actor.note.to_s : actor.instance_variable_get(:@note).to_s
    explain_note(note, lookups)
  end

  def self.explain_note(note, lookups = {})
    result = { :japanese => [], :chinese => [], :unknown => [] }
    note.to_s.each_line do |raw_line|
      line = raw_line.strip
      next if line.empty?

      match = line.match(/\A<([^>]+)>\z/)
      unless match
        result[:unknown] << line
        next
      end

      tag_name = tag_name(match[1])
      next if skipped_tag?(tag_name)

      explanation = explain_tag(tag_name, match[1], lookups)
      if explanation
        [explanation[0]].flatten.each { |text| result[:japanese] << text unless text.to_s.empty? }
        [explanation[1]].flatten.each { |text| result[:chinese] << text unless text.to_s.empty? }
      else
        result[:unknown] << line
      end
    end
    result
  end

  def self.tag_name(content)
    content.to_s.strip.split(/[\s:：]/, 2).first.to_s
  end

  def self.skipped_tag?(name)
    SKIP_TAGS.include?(name.to_s) || name.to_s.start_with?('初期装備')
  end

  def self.translated_name(name)
    value = name.to_s
    return NAME_TRANSLATIONS[value] if NAME_TRANSLATIONS.key?(value)
    return value if NAME_TRANSLATIONS.values.include?(value)

    ''
  end

  def self.lookup_name(collection, id, fallback)
    item = collection && collection[id.to_i]
    name = if item.is_a?(String)
             item
           elsif item.respond_to?(:name)
             item.name.to_s
           elsif item && item.instance_variable_defined?(:@name)
             item.instance_variable_get(:@name).to_s
           else
             ''
           end
    name.empty? ? "#{fallback}#{id}" : name
  end

  def self.skill_type_name(id, lookups)
    lookup_name(lookups[:skill_types], id, '技能类型')
  end

  def self.element_name(id, lookups)
    lookup_name(lookups[:elements], id, '属性')
  end

  def self.state_name(id, lookups)
    lookup_name(lookups[:states], id, '状态')
  end

  def self.parameter_name(id)
    %w[最大HP 最大MP 攻撃力 防御力 魔力 精神力 素早さ 器用さ][id.to_i] || "参数#{id}"
  end

  def self.rate_text(value)
    number = value.to_i
    number >= 0 ? "+#{number}%" : "#{number}%"
  end

  def self.multiplier_text(value)
    number = value.to_i
    delta = number - 100
    delta == 0 ? "×#{number}%" : "×#{number}%（#{delta >= 0 ? '+' : ''}#{delta}%）"
  end

  def self.pairs(body)
    body.to_s.scan(/(\d+)-([+-]?\d+)/)
  end

  def self.explain_tag(tag, content, lookups)
    body = content.to_s.sub(/\A#{Regexp.escape(tag)}\s*/, '')
    case tag
    when '最大HP', '最大MP', '攻撃力', '防御力', '魔力', '精神力', '素早さ', '器用さ'
      value = body.match(/([+-]?\d+)%/)
      return nil unless value
      label = PARAM_TRANSLATIONS[tag]
      return ["#{tag} #{multiplier_text(value[1])}", "#{label} #{multiplier_text(value[1])}"]
    when 'スキルタイプ強化', 'ステート割合強化タイプ', 'ステート固定強化タイプ'
      jp_label = { 'スキルタイプ強化' => '強化',
                   'ステート割合強化タイプ' => 'ステート付与率アップ',
                   'ステート固定強化タイプ' => 'ステート固定強化' }[tag]
      cn_label = { 'スキルタイプ強化' => '强化',
                   'ステート割合強化タイプ' => '状态附加率强化',
                   'ステート固定強化タイプ' => '状态附加固定强化' }[tag]
      jp_lines = []
      cn_lines = []
      pairs(body).each do |id_text, value_text|
        jp_name = skill_type_name(id_text, lookups)
        cn_name = translated_name(jp_name)
        jp_lines << "#{jp_name}#{jp_label} #{rate_text(value_text)}"
        cn_lines << "#{cn_name.empty? ? '' : cn_name}#{cn_label} #{rate_text(value_text)}"
      end
      return nil if jp_lines.empty?
      return [jp_lines, cn_lines]
    when '属性強化'
      jp_lines = []
      cn_lines = []
      pairs(body).each do |id_text, value_text|
        jp_name = element_name(id_text, lookups)
        cn_name = translated_name(jp_name)
        jp_lines << "#{jp_name}属性強化 #{rate_text(value_text)}"
        cn_lines << "#{cn_name.empty? ? '' : cn_name}属性强化 #{rate_text(value_text)}"
      end
      return nil if jp_lines.empty?
      return [jp_lines, cn_lines]
    when '武器強化物理', '武器強化魔法', '武器強化必中'
      jp_label = { '武器強化物理' => '装備時物理強化',
                   '武器強化魔法' => '装備時魔法強化',
                   '武器強化必中' => '装備時万能強化' }[tag]
      cn_label = { '武器強化物理' => '武器物理强化',
                   '武器強化魔法' => '武器魔法强化',
                   '武器強化必中' => '武器必中强化' }[tag]
      jp_lines = []
      cn_lines = []
      pairs(body).each do |id_text, value_text|
        jp_name = lookup_name(lookups[:weapon_types], id_text, '武器类型')
        cn_name = translated_name(jp_name)
        jp_lines << "#{jp_name}#{jp_label} #{rate_text(value_text)}"
        cn_lines << "#{cn_label}（#{cn_name.empty? ? jp_name : cn_name}）#{rate_text(value_text)}"
      end
      return nil if jp_lines.empty?
      return [jp_lines, cn_lines]
    when 'スキル強化', 'ステート割合強化スキル'
      jp_label = tag == 'スキル強化' ? '強化' : 'ステート付与率アップ'
      cn_label = tag == 'スキル強化' ? '技能强化' : '技能状态附加率强化'
      jp_lines = []
      cn_lines = []
      pairs(body).each do |id_text, value_text|
        jp_name = lookup_name(lookups[:skills], id_text, '技能')
        cn_name = translated_name(jp_name)
        jp_lines << "#{jp_name}#{jp_label} #{rate_text(value_text)}"
        cn_lines << if cn_name.empty?
                      "#{cn_label}（技能ID #{id_text}）#{rate_text(value_text)}"
                    else
                      "#{cn_label}「#{cn_name}」 #{rate_text(value_text)}"
                    end
      end
      return nil if jp_lines.empty?
      return [jp_lines, cn_lines]
    when 'TPタイプ消費率'
      pair = body.match(/\A(\d+)\s*,\s*([+-]?\d+)%?/)
      return nil unless pair
      jp_name = skill_type_name(pair[1], lookups)
      cn_name = translated_name(jp_name)
      return ["#{jp_name}TP消費率 #{multiplier_text(pair[2])}",
              "#{cn_name.empty? ? '' : cn_name}TP消耗率 #{multiplier_text(pair[2])}"]
    when 'TP消費率', 'HP消費率', 'MP消費率', 'ゴールド消費率',
         '物理ダメージ率', '魔法ダメージ率'
      value = body.match(/([+-]?\d+)%?/) 
      return nil unless value
      return ["#{tag} #{multiplier_text(value[1])}",
              "#{LABEL_TRANSLATIONS[tag]} #{multiplier_text(value[1])}"]
    when '開始時TP', 'ダメージアップ', '単発スキルダメージアップ',
         '命中率', '回避率', '会心率', '反撃率'
      value = body.match(/([+-]?\d+)%?/) 
      return nil unless value
      return ["#{tag} #{rate_text(value[1])}",
              "#{LABEL_TRANSLATIONS[tag]} #{rate_text(value[1])}"]
    when '属性有効度', '拡張属性有効度', 'ステート有効度', '拡張ステート有効度',
         '弱体有効度', '拡張弱体有効度'
      base_tag = tag.sub(/\A拡張/, '')
      jp_lines = []
      cn_lines = []
      pairs(body).each do |id_text, value_text|
        target = case base_tag
                 when '属性有効度' then element_name(id_text, lookups)
                 when 'ステート有効度' then state_name(id_text, lookups)
                 else parameter_name(id_text)
                 end
        cn_target = translated_name(target)
        jp_label = { '属性有効度' => '属性耐性',
                     'ステート有効度' => 'ステート耐性',
                     '弱体有効度' => '弱体耐性' }[base_tag]
        jp_lines << "#{target}#{jp_label} #{multiplier_text(value_text)}"
        cn_target = "#{base_tag}ID #{id_text}" if cn_target.empty?
        cn_lines << "#{cn_target}#{LABEL_TRANSLATIONS[base_tag]} #{multiplier_text(value_text)}"
      end
      return nil if jp_lines.empty?
      return [jp_lines, cn_lines]
    when '時間停止無視', '即死反転', '二刀流', '三刀流', '両手盾', '夢魔', 'ラーニング'
      return [tag, LABEL_TRANSLATIONS[tag]]
    end
    nil
  end

  def self.load_database(path)
    Marshal.load(File.binread(path))
  end

  def self.load_lookups(root)
    system = load_database(File.join(root, 'Data', 'System.rvdata2'))
    {
      :skill_types => system.instance_variable_get(:@skill_types),
      :elements => system.instance_variable_get(:@elements),
      :weapon_types => system.instance_variable_get(:@weapon_types),
      :skills => load_database(File.join(root, 'Data', 'Skills.rvdata2')),
      :states => load_database(File.join(root, 'Data', 'States.rvdata2'))
    }
  end

  def self.print_result(actor, result)
    name = actor.instance_variable_get(:@name).to_s
    id = actor.instance_variable_get(:@id).to_i
    puts "角色ID #{id}：#{name}"
    puts
    puts '日文说明'
    if result[:japanese].empty?
      puts '（没有识别到常见被动标签）'
    else
      result[:japanese].each { |line| puts "- #{line}" }
    end
    puts
    puts '中文说明'
    if result[:chinese].empty?
      puts '（暂未提供中文翻译）'
    else
      result[:chinese].each { |line| puts "- #{line}" }
    end
    unless result[:unknown].empty?
      puts
      puts '未识别备注（保留原文）'
      result[:unknown].each { |line| puts "- #{line}" }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('..', File.dirname(__FILE__))
  actor_id = (ARGV[0] || '538').to_i
  actors = GouqiActorPassiveExplainer.load_database(File.join(root, 'Data', 'Actors.rvdata2'))
  actor = actors[actor_id]
  abort("Actor ID #{actor_id} does not exist.") unless actor

  lookups = GouqiActorPassiveExplainer.load_lookups(root)
  result = GouqiActorPassiveExplainer.explain_actor(actor, lookups)
  GouqiActorPassiveExplainer.print_result(actor, result)
end
