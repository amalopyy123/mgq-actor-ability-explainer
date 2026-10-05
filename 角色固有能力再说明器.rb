# encoding: UTF-8

# Generate one record per actor trait or non-empty note line.
# Supported entries get translated descriptions; unsupported entries keep raw sources.

require 'csv'
require 'fileutils'
require 'json'
require_relative '角色备注被动能力解释器'

class Table
  def self._load(_data)
    new
  end
end unless defined?(Table)

module RPG
  class Item < UsableItem
  end unless const_defined?(:Item)

  class Class
    class Learning
    end
  end
end

module GouqiActorAbilityReintroducer
  OUTPUT_DIR = File.expand_path('导出CSV', __dir__)
  IMPORTANT_NOTE_TAGS = %w[
    スキルタイプ強化 属性強化 武器強化物理 武器強化魔法 武器強化必中
    スキル強化 ステート割合強化スキル TPタイプ消費率 TP消費率 HP消費率
    MP消費率 ゴールド消費率 物理ダメージ率 魔法ダメージ率 属性有効度
    拡張属性有効度 ステート有効度 拡張ステート有効度 弱体有効度 拡張弱体有効度
    会心ダメージ増加 魔法会心率 拡張会心率 拡張回避率 拡張魔法回避率 必中回避率 拡張必中回避率
    物理反射率 拡張物理反射率 必中反射率 魔法反撃
    開始時TP ダメージアップ 単発スキルダメージアップ スキルチェーン
    チェーン消費軽減 能力値置き換え 能力値加算 属性追加 属性吸収 属性反射
    属性貫通 戦闘開始時発動 ターン終了時発動 オートステート 反撃スキル
    時間停止無視 即死反転 二刀流 三刀流 両手盾 夢魔 ラーニング
  ].freeze

  # These feature codes have a direct and usually meaningful combat effect.
  IMPORTANT_TRAIT_CODES = [11, 13, 21, 22, 23, 31, 32, 33, 34, 41, 43, 51, 52, 55, 61].freeze
  PARAM_NAMES = %w[最大HP 最大MP 攻撃力 防御力 魔力 精神力 素早さ 器用さ].freeze
  # The note syntax uses six combat-stat IDs (zero-based in the note, then +1 in the game script).
  ABILITY_VALUE_NAMES = {
    1 => ['攻撃力', '攻击力'],
    2 => ['防御力', '防御力'],
    3 => ['魔力', '魔力'],
    4 => ['精神力', '精神力'],
    5 => ['素早さ', '敏捷'],
    6 => ['器用さ', '灵巧']
  }.freeze
  XPARAM_NAMES = %w[命中率 回避率 会心率 会心回避率 魔法回避率 魔法反射率 反撃率 ターンHP回復 ターンMP回復 ターンSP回復].freeze
  XPARAM_NAMES_ZH = %w[命中率 闪避率 会心率 会心回避率 魔法闪避率 魔法反射率 反击率 每回合HP恢复 每回合MP恢复 每回合SP恢复].freeze
  # Describe special parameters by their affected gameplay quantity, not as a vague "rate multiplier".
  SPARAM_NAMES = [
    '攻撃対象に選ばれる重み', '防御時に受けるダメージ', '受ける回復量', 'アイテム効果量',
    'MP消費量', 'TP獲得量', '物理ダメージを受ける量', '魔法ダメージを受ける量',
    '地形ダメージを受ける量', '獲得経験値'
  ].freeze
  SPARAM_NAMES_ZH = [
    '被选为攻击目标的权重', '防御时受到的伤害', '受到的恢复量', '药物效果量',
    'MP消耗量', 'SP获得量', '受到的物理伤害', '受到的魔法伤害',
    '受到的地形伤害', '获得经验'
  ].freeze
  STANDARD_EX_CATEGORY_IDS = ((10..35).to_a + [37, 38]).freeze
  # This table mirrors Vocab::EX_CATEGORY in the original and translated game scripts.
  EX_CATEGORY_NAMES = {
    10 => ['ボス', 'Boss'], 11 => ['人間', '人类'], 12 => ['妖魔', '妖魔'],
    13 => ['亜人', '亚人'], 14 => ['淫魔', '淫魔'], 15 => ['吸血鬼', '吸血鬼'],
    16 => ['人魚', '人鱼'], 17 => ['エルフ', '精灵'], 18 => ['妖精', '妖精'],
    19 => ['スライム', '史莱姆'], 20 => ['魔獣', '魔兽'], 21 => ['妖狐', '妖狐'],
    22 => ['ラミア', '拉米亚'], 23 => ['スキュラ', '斯库拉'], 24 => ['鳥', '鸟'],
    25 => ['竜', '龙'], 26 => ['陸棲種', '陆栖种'], 27 => ['海棲種', '海栖种'],
    28 => ['虫', '虫'], 29 => ['植物', '植物'], 30 => ['ゾンビ', '僵尸'],
    31 => ['ゴースト', '幽灵'], 32 => ['ドール', '人偶'], 33 => ['キメラ', '奇美拉'],
    34 => ['天使', '天使'], 35 => ['アポトーシス', '凋零者'],
    37 => ['巨人', '巨人'], 38 => ['ロイド', '机器人'], 39 => ['夢魔', '梦魔'],
    40 => ['飛行', '飞行'], 41 => ['神', '神'], 42 => ['魔王', '魔王']
  }.freeze
  COMMON_STATUS_IDS = ((7..28).to_a + (271..276).to_a).freeze
  STUN_STATUS_IDS = ([22] + (271..276).to_a).freeze
  PARAMETER_DOWN_STATUS_IDS = ([308, 309] + (393..397).to_a).freeze
  PARAMETER_DOWN_EXTENDED_STATUS_IDS = (PARAMETER_DOWN_STATUS_IDS + [398]).freeze
  ELEMENT_WEAKNESS_STATUS_IDS = (75..87).to_a.freeze
  LONG_LIST_THRESHOLD = 10
  STATE_ATTACK_SUMMARY_THRESHOLD = 4
  INLINE_DESCRIPTION_LIMIT = 80
  HASH_PAIR_NOTE_TAGS = %w[
    属性強化 武器強化物理 武器強化魔法 武器強化必中 通常攻撃強化
    ステート割合強化タイプ ステート固定強化タイプ スキルタイプ強化
    ステート割合強化スキル スキル強化
  ].freeze
  PARTY_ACTOR_ABILITY_SUFFIX = '（仅指定角色在当前战斗前4名中时生效；换人后刷新；多个符合条件的伙伴可叠加）'
  ACTOR_NAME_TRANSLATIONS = {
    80 => '希普'
  }.freeze
  # These IDs are intrinsic-only in the current skill and ability data.
  INTRINSIC_ONLY_ABILITY_IDS = [
    873, 874, 875, 876, 880, 6515, 7659, 7706, 8591, 8592, 10035, 10036, 10075
  ].freeze
  INTRINSIC_ONLY_SKILL_IDS = [
    4, 8, 10, 967, 1000, 1134, 1135, 1136, 1491, 1527, 1627, 1628, 1629, 1630,
    1633, 1644, 1658, 1659, 1671, 1674, 1675, 1683, 1809, 1860, 2066, 2067, 2084,
    2105, 2106, 2357, 2514, 2618, 2674, 2753, 2754, 2770, 2824, 2825, 2870, 2871,
    2872, 2875, 2918, 2928, 2929, 2930, 2941, 3009, 3089, 3106, 3107, 3108, 3109,
    3154, 3155, 3156, 3157, 3158, 3159, 3160, 3162, 3165, 3169, 3170, 3171, 3172,
    3174, 3175, 5765, 5766, 5767, 5768, 5769, 5770, 5771, 5772, 5773, 5774, 5775,
    5776, 5777, 5778, 5779, 5780, 5781, 5782, 5783, 5784, 5785, 5786, 5787, 5789,
    5790, 5791, 5792, 5793, 5794, 5795, 5796, 5797, 5798, 5799, 5800, 5801, 5802,
    5803, 5804, 5805, 5807, 5808, 5809, 5810, 5811, 5812, 5813, 5814, 5815, 5816,
    5817, 5818, 5819, 5820, 5823, 5824, 5825, 5826, 5827, 5828, 5829, 5830, 5831,
    5833, 5834, 5835, 5836, 5843, 5844, 5845, 5846, 5847, 5863, 5864, 5865, 5866,
    5867, 5868, 5869, 5870, 5871, 5872, 5873, 5874, 5875, 5876, 5877, 5878, 5879,
    5881, 5882, 5883, 5884, 5886, 5887, 5889, 5890, 5891, 5892, 5893, 5894, 5895,
    5896, 5897, 5898, 5899, 5900, 5901, 5902, 5904, 5905, 5906, 5907, 5908, 5909,
    5910, 6221, 9024, 9172, 9173, 9213, 9266, 9286, 9292, 9562, 9622, 9780, 9781,
    9808, 10101
  ].freeze
  INTRINSIC_LEARNING_SPECIAL_ACTORS = [143, 540, 542, 603, 611].freeze
  MISSING_SOURCE_RAW_DESCRIPTIONS = {
    4 => ['两次行动', '混沌属性以外的伤害无效化', '受到的混沌属性的伤害变为1/4'],
    287 => ['可以使用自然感应'],
    484 => ['「枪技」连续发动两次'],
    497 => ['反击率大幅提升并且攻击力提升3级'],
    534 => ['敏捷大幅提升'],
    684 => ['物理属性附加暗属性'],
    732 => ['可以装备法杖'],
    733 => ['可以装备法杖'],
    738 => ['物理攻击附加生化属性', '生化属性伤害强化'],
    748 => ['医术、暗技的暗秽附加率提升'],
    751 => ['会心率提升'],
    762 => ['可以装备重装防具'],
    766 => ['医术、尸技的MP消耗减半'],
    773 => ['敏捷和灵巧大幅提升'],
    775 => ['对天使特攻伤害'],
    782 => ['可以装备巨剑'],
    866 => ['物理攻击完全回避', '万能回避率提升30%'],
    867 => ['弓技SP消耗变为2/3'],
    868 => ['鞭技SP消耗变为2/3'],
    869 => ['格斗SP消耗变为2/3'],
    873 => ['白魔法、黑魔法、时魔法、海技附加减速和停止状态'],
    896 => ['回合结束时频繁发动黏滑、拘束捕食技'],
    907 => ['阴阳术、忍术、造技顽强发动'],
    998 => ['可以使用枪技'],
    999 => ['可以使用触手技']
  }.freeze
  MISSING_SOURCE_RAW_EXTRA_COMMENTS = {
    4 => '角色自身的底层特性和备注标签中没有找到这三项效果的直接实现：未配置通常用于追加行动的code=61特性，也未发现“混沌属性以外的伤害无效化”及“受到的混沌属性伤害变为1/4”对应的角色特性或备注标签。',
    287 => '角色自身的特性和备注中没有配置自然感应（技能类型ID 61）的使用权限，即未配置code=41、data_id=61。不过角色当前拥有的种族“上级梦魔”“小恶魔”“梦魔”均可提供自然感应的使用权限，因此角色在当前种族配置下实际可以使用自然感应；该权限来自种族，不是角色自身的直接固有特性。',
    534 => '固有能力说明写有“敏捷和回避率大幅提升”，但角色自身及其关联对象中均未找到提升敏捷的参数特征或备注标签。实际仅配置<拡張回避率 15%>，即回避率提升15%；敏捷不会因此提升。',
    684 => '角色特性和备注中均未找到物理属性追加暗属性的配置（例如<属性追加 1,10>）；实际没有该效果。',
    732 => '角色特性中有拳装备权限（code=51, data_id=11），但没有法杖装备权限（code=51, data_id=17）；实际未配置法杖装备资格。',
    733 => '角色特性中有拳装备权限（code=51, data_id=11），但没有法杖装备权限（code=51, data_id=17）；实际未配置法杖装备资格。',
    738 => '角色备注<属性追加 1,51>只为物理属性攻击追加修罗属性，未找到追加生化属性（属性ID 36）或强化生化属性伤害的配置；实际只有修罗属性相关效果。',
    748 => '未找到使医术（技能类型ID 45）或暗技（ID 27）附加暗秽（状态ID 43）的特性或备注。已有备注<ステート特攻スキルタイプ 27-43-100,45-43-100,53-43-100>只会提高暗技、医术、兽技对已处于暗秽状态目标的特攻伤害，不会使技能附加暗秽状态。',
    751 => '角色的会心率特性为默认值5%，未找到额外提升会心率的配置。备注<会心ダメージ増加:50>实际只使会心伤害增加50%，不提升会心率。',
    762 => '角色特性中有拳装备权限（code=51, data_id=11），但未找到重装防具对应的装备权限特性；固有能力所述重装防具装备资格未配置。',
    766 => '技能类型消耗备注使铳技、召唤术、医术、尸技的SP消耗均减半；MP消耗备注只使铳技和召唤术的MP消耗减半，没有配置医术（技能类型ID 45）或尸技（ID 59）的MP消耗减半。',
    773 => '角色特性中没有提升基础敏捷或灵巧的参数特性。备注<能力値加算 9,1,5,50>和<能力値加算 9,6,5,50>只在计算刀技的攻击力、灵巧时分别追加敏捷的50%，不会提高角色的基础敏捷或灵巧。',
    775 => '角色特性和备注中均未找到对天使类别造成特攻伤害的配置；固有能力所述天使特攻没有对应的底层效果。',
    782 => '角色已有剑（code=51, data_id=2）、骑士剑（ID 3）、刀（ID 9）、忍者刀（ID 10）、棍（ID 14）和镰（ID 15）的装备权限，但没有巨剑装备权限（code=51, data_id=4）。',
    866 => '角色自身的特性和备注中未找到物理完全回避或提升回避率的配置。',
    867 => '角色自身的特性和备注中未找到弓技（技能类型ID 14）的SP消耗倍率配置。',
    868 => '角色自身的特性和备注中未找到鞭技（技能类型ID 15）的SP消耗倍率配置。',
    869 => '角色自身的特性和备注中未找到格斗（技能类型ID 21）的SP消耗倍率配置。',
    873 => '该角色确有回合结束时以50%概率发动技能的备注<ターン終了時発動 1: 9563,50%>，但没有配置技能附加减速或停止状态的标签。其<ステート特攻スキルタイプ>只会提高对已处于减速、停止状态目标的伤害，不会给目标附加这些状态。',
    896 => '角色备注配置了<回避時スキル 2803,100%>，即闪避时以100%概率发动技能ID 2803；未找到回合结束时自动发动该技能的配置。',
    907 => '备注<スキルタイプ強化 29-50,31-50,60-50>使阴阳术、忍术、造技威力提高50%；未找到这些技能类型对应的<頑強スキルタイプ>或<頑強スキル>标签。',
    998 => '角色自身特性未配置枪技（技能类型ID 10）的使用权限；角色已通过种族获得吐息使用权限。',
    999 => '角色自身特性未配置触手技（技能类型ID 55）的使用权限；角色已通过种族获得触手技使用权限。'
  }.freeze
  DIRECT_PERCENT_NOTE_LABELS = {
    '会心ダメージ増加' => ['会心ダメージ増加', '会心伤害增加'],
    '魔法会心率' => ['魔法会心率', '魔法会心率'],
    '拡張会心率' => ['拡張会心率', '会心率'],
    '拡張回避率' => ['拡張回避率', '闪避率'],
    '拡張魔法回避率' => ['拡張魔法回避率', '魔法闪避率'],
    '必中回避率' => ['必中回避率', '必中闪避率'],
    '拡張必中回避率' => ['拡張必中回避率', '必中闪避率'],
    '物理反射率' => ['物理反射率', '物理反射率'],
    '拡張物理反射率' => ['物理反射率', '物理反射率'],
    '必中反射率' => ['必中反射率', '必中反射率'],
    '魔法反撃' => ['魔法反撃', '魔法反击']
  }.freeze
  SUSPECTED_ATTRIBUTE_ID_NOTES = {
    [898, 14] => '原标签按属性追加解析，但属性ID 14 与该角色相邻能力中的冻结状态ID相同，疑似作者误将状态ID写入属性参数。',
    [899, 13] => '原标签按属性追加解析，但属性ID 13 与该角色相邻能力中的燃烧状态ID相同，疑似作者误将状态ID写入属性参数。',
    [900, 15] => '原标签按属性追加解析，但属性ID 15 与该角色相邻能力中的电击状态ID相同，疑似作者误将状态ID写入属性参数。'
  }.freeze
  ACTOR_NOTE_CORRECTIONS = {
    [28, '<TPタイプ消費率 14-133,26-133>'] => '固有能力描述写成「弓技」「白魔法」「圣技」的MP和SP消耗均增加1/3，但原始备注实际只将弓技（技能类型ID 14）和圣技（技能类型ID 26）的SP消耗量变为133%（增加33%）。白魔法（技能类型ID 22）没有配置SP消耗增加，同时也没有配置这三类技能的MP消耗增加，因此实际效果与固有能力描述不符。',
    [5, '<HP消費率 50%>'] => '固有能力描述写成使用暗属性技能时HP消耗减半，但原始备注<HP消費率 50%>设置的是不区分技能类型的全局HP消耗倍率。实际所有需要消耗HP的技能，其HP消耗量都会变为原来的50%（减少50%），并非只作用于暗属性技能。',
    [6, '<HP消費率 25%>'] => '固有能力描述写成使用暗属性技能时HP消耗变为1/4，但原始备注<HP消費率 25%>设置的是不区分技能类型的全局HP消耗倍率。实际所有需要消耗HP的技能，其HP消耗量都会变为原来的25%（减少75%），并非只作用于暗属性技能。',
    [7, '<HP消費率 0%>'] => '固有能力描述写成使用暗属性技能时不消耗HP，但原始备注<HP消費率 0%>设置的是不区分技能类型的全局HP消耗倍率。实际所有需要消耗HP的技能，其HP消耗量都会变为0，并非只作用于暗属性技能。',
    [23, '<ステート特攻スキルタイプ 16-21-150,16-308-150,16-309-150,16-393-150,16-394-150,16-395-150,16-396-150,16-397-150,16-398-150,52-21-150,52-308-150,52-309-150,52-393-150,52-394-150,52-395-150,52-396-150,52-397-150,52-398-150>'] => '固有能力描述写成「投掷技」「粘液技」对黏滑及弱化状态的敌人可造成大量特攻伤害，但原始备注实际配置的是这两类技能对消化（状态ID 21）及各类能力下降状态（状态ID 308、309、393至398）的特攻伤害 +150%，没有配置对黏滑（状态ID 23）的特攻。因此敌人仅处于黏滑状态时不会触发这项特攻。',
    [98, '<スキルステート自己付加 2624-2-100,2625-2-100,2632-2-100>'] => '固有能力描述笼统写成使用泡技能时进入防御姿态，但原始备注实际只列出了技能ID 2624、2625和2632。其中技能ID 2632没有有效的技能数据，因此实际有效的对象只有技能ID 2624和2625；高阶泡技能ID 9560、9561未包含在该标签中，使用它们不会触发防御姿态。',
    [239, '<ステート特攻スキルタイプ 58-21-100,58-21-100>'] => '固有能力描述写成「植物技」对处于消化或恍惚状态的敌人可造成特攻伤害，但原始备注只配置了对消化（状态ID 21）的特攻，并且相同的58-21-100配置重复了两次；没有配置对恍惚（状态ID 25）的特攻。因此实际效果是植物技对消化的特攻增幅合计 +200%，对仅处于恍惚状态的敌人不会触发这项特攻。',
    [253, '<ステート割合強化スキル 2556-30,2751-30,2752-30>'] => '固有能力描述写成「魔技」「蛇技」的石化发生率提升，容易理解为对这两个技能类型整体生效；但原始备注<ステート割合強化スキル>按具体技能ID判定，实际只使技能ID 2556「石化的魔眼」、2751「石化攻击」和2752「石化乱击」的异常状态附加率提高30%，不会自动强化其他魔技或蛇技的石化附加率。',
    [255, '<ステート割合強化スキル 3085-30>'] => '固有能力描述写成「吐息」的中毒发生率提升，容易理解为对吐息技能类型整体生效；但原始备注<ステート割合強化スキル 3085-30>只指定了技能ID 3085「毒息」，实际仅使该技能的异常状态附加率提高30%，不会自动强化其他吐息技能的中毒附加率。',
    [310, '<スキルタイプ強化 51-30,54-30,62-30,69-30>'] => '固有能力描述写成「海技」「兽技」「蛇技」「吐息」「巨技」的威力提升，但原始备注实际只配置了海技（技能类型ID 51）、蛇技（ID 54）、吐息（ID 62）和巨技（ID 69）的威力 +30%，没有配置兽技（ID 53）。因此兽技不会获得这项威力强化。',
    [396, '<スキルタイプ強化 23-50,15-50,61-50,67-50>'] => '固有能力描述写成「黑魔法」「鞭技」「淫技」「自然感应」「念动」的威力大幅提升，但原始备注实际只配置了黑魔法（技能类型ID 23）、鞭技（ID 15）、自然感应（ID 61）和念动（ID 67）的威力 +50%，没有配置淫技（ID 49）。因此淫技不会获得这项威力强化。',
    [455, '<スキルチェーン 17,58>'] => '固有能力描述写成「植物技」可以连锁发动「铁球技」，但原始备注<スキルチェーン 17,58>实际指定的顺序是铁球技（技能类型ID 17）→植物技（ID 58），即先使用铁球技，再连锁发动植物技；连锁顺序与固有能力描述相反。',
    [488, '<オートステート 399>'] => '固有能力描述写成战斗开始时自动发动攻击，但原始备注<オートステート 399>实际是在战斗开始时自动附加状态ID 399「攻击力上升」，不会执行普通攻击或其他攻击动作。固有能力描述很可能混淆了“攻击力上升”和“自动攻击”。',
    [489, '<スキルチェーン 26,21,26>'] => '固有能力描述写成「投掷技或白魔法→格斗→圣技」，但原始备注<スキルチェーン 26,21,26>实际指定的是圣技（技能类型ID 26）→格斗（ID 21）→圣技（ID 26）。投掷技的技能类型ID是16，因此这条技能链不能由投掷技起手，很可能是作者误将16写成了26；另一条「白魔法→格斗→圣技」技能链可以正常发动。',
    [522, '<スキルタイプステート自己付加 7-399-100,7-400-100,23-399-100,23-400-100>'] => '固有能力描述写成使用「剑技」「黑魔法」时有几率使攻击力或魔力提升，但原始备注实际表示：使用剑技或黑魔法时，均会以100%概率分别附加「攻击力上升」和「魔力上升」。两个状态会同时附加，并非概率触发，也不是二选一。',
    [922, '<スキルタイプステート自己付加 7-399-100,7-400-100,23-399-100,23-400-100,46-399-100,46-400-100>'] => '固有能力描述写成使用剑技、黑魔法、侍奉时有几率使攻击力或魔力提升；实际使用这三类技能时，均会以100%概率同时附加「攻击力上升」和「魔力上升」，并非概率触发或二选一。',
    [923, '<スキルタイプステート自己付加 6-399-100,6-400-100,23-399-100,23-400-100,30-399-100,30-400-100>'] => '固有能力描述写成使用短剑技、黑魔法、盗贼技时有几率使攻击力或魔力提升；实际使用这三类技能时，均会以100%概率同时附加「攻击力上升」和「魔力上升」，并非概率触发或二选一。',
    [873, '<ステート特攻スキルタイプ 22-16-150,23-16-150,51-16-150,22-17-150,23-17-150,51-17-150>'] => '该标签提升白魔法、黑魔法、海技对已处于减速或停止状态目标的特攻伤害 +150%；它不会使技能附加减速或停止状态。角色另有回合结束时50%概率发动技能ID 9563的标签。',
    [843, '<MPタイプ消費率 22-50,26-50>'] => '这条备注仅将白魔法和圣技的MP消耗量设为原来的50%；棍技没有配置MP消耗减半。角色另有SP消耗备注，但该备注仅指定棍技和圣技，未指定白魔法。',
    [890, '<MPタイプ消費率 26-66,29-66,31-66,53-66>'] => '备注将这些技能类型的MP消耗量设为原来的66%，即减少34%，并非减半；同一角色的SP消耗备注也使用66%的倍率。',
    [843, '<TPタイプ消費率 12-50,26-50>'] => '固有能力描述写成棍技、白魔法、圣技的MP和SP消耗均减半；实际SP消耗减半的只有棍技和圣技，MP消耗减半的只有白魔法和圣技。棍技没有配置MP消耗减半，白魔法没有配置SP消耗减半。',
    [854, '<code=11, data_id=50, value=0.25>'] => '属性ID 50是终焉属性，不是修罗属性（ID 51）。角色受到终焉属性伤害时伤害变为25%（减少75%）；自身特性和备注中未找到修罗属性抗性。',
    [890, '<TPタイプ消費率 26-66,29-66,31-66,53-66>'] => '备注将这些技能类型的SP消耗量设为原来的66%，即减少34%，并非减半；同一角色的MP消耗备注也使用66%的倍率。',
    [911, '<物理反射率 100%>'] => '这条备注明确配置物理反射率 +100%；角色另有魔法反射率 +100% 的特性，以及<必中反射率 30%>备注。因此“物理和万能反射缺少source_raw”的判断不成立。',
    [911, '<必中反射率 30%>'] => '这条备注明确配置必中反射率 +30%；角色另有<物理反射率 100%>备注和魔法反射率 +100% 的特性。因此“物理和万能反射缺少source_raw”的判断不成立。',
    [647, '<スキルタイプステート敵付加 69-271-50>'] => '固有能力描述写成使用「造技」会频繁使敌人陷入眩晕状态，但原始备注实际指定的是使用「巨技」（技能类型ID 69）时，以50%概率对敌人附加「眩晕1」状态。「造技」的技能类型ID为60，因此造技不会获得该状态附加效果；固有能力描述与实际配置不一致。',
    [645, '<連続発動タイプ 9-2>'] => '固有能力中的另一条说明称「刀技」连击技能的命中次数增加2次，但原始备注<連続発動タイプ 9-2>控制的是刀技连续发动次数，不会修改单个技能的命中段数。该标签在角色备注中出现两次，重复项会按脚本规则分别保留并累加；应与“连击技能的Hit数增加”区分。',
    [751, '<スキルチェーン 17,54,27>'] => '固有能力说明列出的连锁顺序是暗技→蛇技→铁球技；但原始备注中的技能类型ID对应铁球技（17）→蛇技（54）→暗技（27），实际顺序与说明完全相反。',
    [675, '<反撃強化 2900%>'] => '固有能力说明称攻击力提升3级，但原始备注<反撃強化 2900%>提升的是反击伤害：在基础倍率上增加2900%，即反击伤害变为×3000%（30倍）。同组的code=22、data_id=6特性提升反击率75%；没有发现攻击力上升状态或攻击力参数强化，因此“攻击力提升3级”与实际效果不符。',
    [684, '<属性強化 50-30>'] => '固有能力说明称暗属性攻击威力提升，但原始备注指定属性ID 50（终焉属性），实际是终焉属性威力 +30%；暗属性的ID为10。',
    [694, '<TPタイプ消費率 7-200,26-200,27-200,70-200>'] => '固有能力说明称这些技能的SP消耗“增加1/2”，即增加50%；原始备注实际将技能类型ID 7、26、27、70的SP消耗量设为×200%（增加100%，即翻倍），数值与说明不符。',
    [709, '<属性強化 10-50>'] => '固有能力说明称终焉属性攻击威力大幅提升，但原始备注指定属性ID 10（暗属性），实际是暗属性威力 +50%；终焉属性的ID为50。',
    [710, '<属性強化 10-50>'] => '固有能力说明称终焉属性攻击威力大幅提升，但原始备注指定属性ID 10（暗属性），实际是暗属性威力 +50%；终焉属性的ID为50。',
    [711, '<属性強化 10-50>'] => '固有能力说明称终焉属性攻击威力大幅提升，但原始备注指定属性ID 10（暗属性），实际是暗属性威力 +50%；终焉属性的ID为50。',
    [712, '<属性強化 10-50>'] => '固有能力说明称终焉属性攻击威力大幅提升，但原始备注指定属性ID 10（暗属性），实际是暗属性威力 +50%；终焉属性的ID为50。',
    [714, '<属性強化 50-30>'] => '固有能力说明称暗属性攻击威力提升，但原始备注指定属性ID 50（终焉属性），实际是终焉属性威力 +30%；暗属性的ID为10。',
    [653, '<必中回避率 30%>'] => '固有能力说明中的“万能回避率”有对应备注<必中回避率 30%>（必中闪避率 +30%），因此不能判定为缺少第三项回避相关来源；普通回避率与魔法回避率则分别由角色特性提升30%。',
    [674, '<必中回避率 30%>'] => '固有能力说明中的“万能回避率”有对应备注<必中回避率 30%>（必中闪避率 +30%），因此不能判定为缺少第三项回避相关来源；普通回避率与魔法回避率则分别由角色特性提升30%。',
    [677, '<必中回避率 30%>'] => '固有能力说明中的“万能回避率”有对应备注<必中回避率 30%>（必中闪避率 +30%），因此不能判定为缺少第三项回避相关来源；普通回避率与魔法回避率则分别由角色特性提升30%。',
    [671, '<ステート特攻スキルタイプ 8-28-150,15-28-150>'] => '固有能力描述写成对处于拘束状态的敌人使用「尖剑技」「触手技」可造成大量特攻伤害，但原始备注实际指定的是尖剑技（技能类型ID 8）和鞭技（技能类型ID 15）对拘束的特攻伤害 +150%，没有配置触手技（技能类型ID 55）。因此鞭技可以获得该特攻，触手技不能获得该特攻。',
    [678, '<属性追加 1,6>'] => '固有能力描述只说明物理、风属性攻击会附加强子属性，但原始备注还包含<属性追加 1,6>，会使物理属性攻击同时附加风属性；这一额外效果未在固有能力描述中提及。',
    [732, '<ステート特攻スキルタイプ 21-43-100,24-43-100,27-43-100,60-43-100>'] => '固有能力描述写成对减速、停止或暗秽状态的敌人使用「格斗」「时魔法」「暗技」「造技」可造成特攻伤害，但原始备注只配置了对暗秽状态（状态ID 43）的特攻伤害 +100%，没有配置减速（状态ID 16）或停止（状态ID 17）。因此敌人仅处于减速或停止状态时不会触发该特攻。',
    [733, '<ステート特攻スキルタイプ 21-43-100,24-43-100,27-43-100>'] => '固有能力描述写成对减速、停止或暗秽状态的敌人使用「格斗」「时魔法」「暗技」可造成特攻伤害，但原始备注只配置了对暗秽状态（状态ID 43）的特攻伤害 +100%，没有配置减速（状态ID 16）或停止（状态ID 17）。因此敌人仅处于减速或停止状态时不会触发该特攻。',
    [736, '<能力値置き換え 60,1,5>'] => '固有能力描述写成「造技」「吐息」的威力取决于魔力，但原始备注实际只配置了造技：计算攻击力时取攻击力与敏捷中的较高值，计算灵巧时取灵巧与敏捷中的较高值。标签没有使用魔力（能力值ID 3），也没有为吐息（技能类型ID 62）配置能力值替换，因此实际效果与固有能力描述不符。',
    [736, '<能力値置き換え 60,6,5>'] => '固有能力描述写成「造技」「吐息」的威力取决于魔力，但原始备注实际只配置了造技：计算攻击力时取攻击力与敏捷中的较高值，计算灵巧时取灵巧与敏捷中的较高值。标签没有使用魔力（能力值ID 3），也没有为吐息（技能类型ID 62）配置能力值替换，因此实际效果与固有能力描述不符。',
    [740, '<スキルタイプステート敵付加 10-43-15,27-43-15>'] => '固有能力描述写成「枪技」「暗技」「造技」的暗秽附加率提升，但原始备注只配置了枪技（技能类型ID 10）和暗技（技能类型ID 27）以15%概率附加暗秽状态，没有配置造技（技能类型ID 60）。因此造技不会获得该暗秽附加效果。',
    [753, '<チェーン消費軽減 25%>'] => '固有能力描述写成连锁发动技能的MP和SP消耗减半（减少50%），但原始备注<チェーン消費軽減 25%>实际会使技能链中的MP和SP消耗量均变为原来的25%（减少75%），并非减半。',
    [754, '<チェーン消費軽減 25%>'] => '固有能力描述写成连锁发动技能的MP和SP消耗减半（减少50%），但原始备注<チェーン消費軽減 25%>实际会使技能链中的MP和SP消耗量均变为原来的25%（减少75%），并非减半。',
    [758, '<スキルタイプステート敵付加 13-14-25,13-19-25,13-43-25,29-14-25,29-19-25,29-43-25,31-14-25,31-19-25,31-43-25,44-14-25,44-19-25,44-43-25,59-14-25,59-19-25,59-43-25>'] => '固有能力描述写成「镰技」「忍术」「阴阳术」「料理」「尸技」会附加即死、冻结、僵尸和暗秽效果，但原始备注实际只配置了冻结（状态ID 14）、僵尸（状态ID 19）和暗秽（状态ID 43），附加概率均为25%；没有配置即死效果。',
    [776, '<チェーン消費軽減 25%>'] => '固有能力描述写成连锁发动技能的MP和SP消耗减半（减少50%），但原始备注<チェーン消費軽減 25%>实际会使技能链中的MP和SP消耗量均变为原来的25%（减少75%），并非减半。',
    [779, '<チェーン消費軽減 25%>'] => '固有能力描述写成连锁发动技能的MP和SP消耗减半（减少50%），但原始备注<チェーン消費軽減 25%>实际会使技能链中的MP和SP消耗量均变为原来的25%（减少75%），并非减半。',
    [780, '<チェーン消費軽減 25%>'] => '固有能力描述写成连锁发动技能的MP和SP消耗减半（减少50%），但原始备注<チェーン消費軽減 25%>实际会使技能链中的MP和SP消耗量均变为原来的25%（减少75%），并非减半。',
    [784, '<属性追加 4,44>'] => '固有能力描述写成水属性附加纳米属性，但原始备注<属性追加 4,44>实际表示冰属性（属性ID 4）附加量子属性（属性ID 44）。水属性和纳米属性的ID分别为8和48，因此固有能力描述与实际配置完全不符。',
    [784, '<属性強化 44-100>'] => '固有能力描述写成纳米属性攻击的威力达到极致提升，但原始备注<属性強化 44-100>实际使量子属性（属性ID 44）强化 +100%。纳米属性的ID为48，因此固有能力描述与实际配置不符。',
    [798, '<HPタイプ消費率 6-0,7-0,8-0,9-0,10-0,13-0,14-0,15-0,18-0,19-0,21-0,24-0,27-0,29-0,31-0,33-0,38-0,40-0,45-0,47-0,48-0,50-0,51-0,57-0,60-0,62-0,67-0>'] => '固有能力描述写成使用暗属性技能时不消耗MP，但原始备注实际将指定技能类型的HP消耗量变为0%，不会免除MP消耗。另一条<HPスキル消費率>标签也只免除指定技能的HP消耗；两条标签都没有配置MP消耗减免。',
    [798, '<HPスキル消費率 11-0,1594-0,1596-0,9249-0,9253-0,9256-0,9258-0,9259-0,9260-0,9264-0,9265-0>'] => '固有能力描述写成使用暗属性技能时不消耗MP，但原始备注实际将指定技能的HP消耗量变为0%，不会免除MP消耗。另一条<HPタイプ消費率>标签也只免除指定技能类型的HP消耗；两条标签都没有配置MP消耗减免。',
    [807, '<窮地スキルタイプ強化 22-100,25-100>'] => '固有能力描述写成HP越少，「黑魔法」「召唤」越强，但原始备注实际配置的是白魔法（技能类型ID 22）和召唤（技能类型ID 25）的濒死强化 +100%，没有配置黑魔法（技能类型ID 23）。因此实际得到强化的是白魔法和召唤，而不是黑魔法和召唤。',
    [815, '<スキルタイプステート敵付加 74-7-80,74-19-80>'] => '固有能力描述写成「剑技」「铳技」附加出血效果，但原始备注实际作用于技能类型ID 74；当前数据库中ID 74没有对应的技能类型，因此该效果通常无法触发。即使能够触发，配置的也分别是以80%概率附加中毒（状态ID 7）和僵尸（状态ID 19），并非出血。',
    [821, '<ステート特攻スキルタイプ 21-26-100>'] => '固有能力描述写成对处于恍惚状态的敌人使用「格斗」可造成特攻伤害，但原始备注实际配置的是格斗对诱惑（状态ID 26）的特攻伤害 +100%，而恍惚的状态ID为25。因此该特攻对诱惑状态生效，不会因敌人仅处于恍惚状态而生效。',
    [843, '<スキルチェーン 22,12,26,70>'] => '固有能力描述写成「白魔法」「圣技」「棍技」「混沌」可按顺序连锁发动，但原始备注实际顺序为白魔法（22）→棍技（12）→圣技（26）→混沌（70）；圣技与棍技的触发顺序与固有能力描述相反。',
    [845, '<属性強化 10-49,10-50>'] => '固有能力描述写成永劫、终焉属性攻击的威力大幅提升，但原始备注实际把属性ID 10（暗属性）重复设置为49%和50%；游戏按该备注的最后一个值计算，因此实际生效的是暗属性强化+50%，永劫（属性ID 49）和终焉（属性ID 50）均未获得这项强化。',
    [859, '<スキルチェーン 16,52,22>'] => '固有能力描述写成「粘液技」「投掷技」「白魔法」可按顺序连锁发动，但原始备注实际顺序为投掷技（16）→粘液技（52）→白魔法（22），与固有能力描述相反。',
    [865, '<連続発動タイプ 19-3>'] => '固有能力描述写成「铳技」连续发动4次，但原始备注<連続発動タイプ 19-3>实际表示铳技连续发动3次，因此实际发动次数比文本少1次。',
    [875, '<ステート特攻スキルタイプ 15-24-150,15-25-150,15-26-150,15-27-150,15-28-150>'] => '固有能力描述写成对拘束及快乐状态异常的敌人使用「植物技」「鞭技」可造成大量特攻伤害，但原始备注只配置了鞭技（技能类型ID 15）对敏感、恍惚、诱惑、失禁和拘束的特攻伤害 +150%，没有配置植物技（技能类型ID 58）。因此植物技不会获得这些特攻效果。',
    [891, '<属性強化 47-50>'] => '固有能力描述写成银河属性攻击的威力大幅提升，但原始备注<属性強化 47-50>实际强化的是大地属性（属性ID 47）+50%；银河属性的ID为41，因此银河属性没有获得这项强化。',
    [902, '<スキルタイプ強化 55-30,69-30>'] => '固有能力描述写成「触手技」「巨技」的威力最大化提升，但原始备注实际只提供触手技和巨技各+30%的威力强化，属于普通数值强化，并非文本所称的最大化提升。',
    [902, '<能力値加算 69,1,6,50>'] => '固有能力描述写成「巨技」的威力附加全部灵巧，但原始备注<能力値加算 69,1,6,50>实际表示巨技计算攻击力时额外加上灵巧的50%，并非100%灵巧。',
    [920, '<チェーン消費軽減 12%>'] => '固有能力描述写成技能连锁发动时的MP、SP消耗量变为25%，但原始备注<チェーン消費軽減 12%>实际使技能链中的消耗量变为原来的12%（减少88%），效果比文本说明更强。'
  }.freeze
  LONG_TARGET_OVERRIDES = {
    [26, 'MPスキル消費率'] => ['聖属性スキル', '圣属性技能'],
    [729, 'MPスキル消費率'] => ['英雄技に属する魔法', '「英雄技」中的魔法'],
    [799, 'MPスキル消費率'] => ['聖属性スキル', '圣属性技能'],
    [886, 'MPスキル消費率'] => ['魔眼スキル', '魔眼技能'],
    [104, 'TPスキル消費率'] => ['糸を使うスキル', '使用丝线的技能'],
    [127, 'TPスキル消費率'] => ['弱体系スキル', '弱化系技能'],
    [140, 'TPスキル消費率'] => ['糸を使うスキル', '使用丝线的技能'],
    [157, 'TPスキル消費率'] => ['糸を使うスキル', '使用丝线的技能'],
    [192, 'TPスキル消費率'] => ['乳房を使うスキル', '使用乳房的技能'],
    [251, 'TPスキル消費率'] => ['乳房を使うスキル', '使用乳房的技能'],
    [292, 'TPスキル消費率'] => ['乳房を使うスキル', '使用乳房的技能'],
    [330, 'TPスキル消費率'] => ['糸を使うスキル', '使用丝线的技能'],
    [429, 'TPスキル消費率'] => ['人形召喚スキル', '人偶召唤技能'],
    [448, 'TPスキル消費率'] => ['糸を使うスキル', '使用丝线的技能'],
    [17, 'スキル強化'] => ['英雄技に属する魔法', '「英雄技」中的魔法'],
    [127, 'スキル強化'] => ['弱体系スキル', '弱化系技能'],
    [140, 'スキル強化'] => ['糸を使うスキル', '使用丝线的技能'],
    [151, 'スキル強化'] => ['牙を使うスキル', '使用牙的技能'],
    [154, 'スキル強化'] => ['牙を使うスキル', '使用牙的技能'],
    [157, 'スキル強化'] => ['糸を使うスキル', '使用丝线的技能'],
    [165, 'スキル強化'] => ['手淫系スキル', '手淫系技能'],
    [177, 'スキル強化'] => ['牙を使うスキル', '使用牙的技能'],
    [235, 'スキル強化'] => ['糸を使うスキル', '使用丝线的技能'],
    [250, 'スキル強化'] => ['自爆スキル', '自爆技能'],
    [251, 'スキル強化'] => ['乳房を使うスキル', '使用乳房的技能'],
    [335, 'スキル強化'] => ['吸血スキル', '吸血技能'],
    [336, 'スキル強化'] => ['吸血スキル', '吸血技能'],
    [337, 'スキル強化'] => ['吸血スキル', '吸血技能'],
    [412, 'スキル強化'] => ['陰陽剣技スキル', '阴阳剑技技能'],
    [429, 'スキル強化'] => ['人形召喚スキル', '人偶召唤技能'],
    [448, 'スキル強化'] => ['糸を使うスキル', '使用丝线的技能'],
    [463, 'スキル強化'] => ['手を使う快楽攻撃スキル', '用手进行的快乐攻击技能'],
    [648, 'スキル強化'] => ['乳房を使うスキル', '使用乳房的技能'],
    [883, 'スキル強化'] => ['乳房を使うスキル', '使用乳房的技能'],
    [886, 'スキル強化'] => ['魔眼スキル', '魔眼技能'],
    [913, 'スキル強化'] => ['魔眼スキル', '魔眼技能'],
    [168, 'ステート割合強化スキル'] => ['魔眼スキル', '魔眼技能'],
    [251, 'ステート割合強化スキル'] => ['乳房を使うスキル', '使用乳房的技能'],
    [886, 'ステート割合強化スキル'] => ['魔眼スキル', '魔眼技能'],
    [192, '連続発動スキル'] => ['乳房を使うスキル', '使用乳房的技能'],
    [292, '連続発動スキル'] => ['乳房を使うスキル', '使用乳房的技能'],
    [330, '連続発動スキル'] => ['糸を使うスキル', '使用丝线的技能'],
    [463, '連続発動スキル'] => ['手を使う快楽攻撃スキル', '用手进行的快乐攻击技能'],
    [648, '連続発動スキル'] => ['乳房を使うスキル', '使用乳房的技能'],
    [650, '連続発動スキル'] => ['幽霊召喚スキル', '幽灵召唤技能'],
    [729, '連続発動スキル'] => ['英雄技に属する魔法', '「英雄技」中的魔法'],
    [883, '連続発動スキル'] => ['乳房を使うスキル', '使用乳房的技能'],
    [21, '連続発動タイプ'] => ['魔法および忍術', '魔法和忍术'],
    [22, '連続発動タイプ'] => ['魔法および忍術', '魔法和忍术'],
    [682, '連続発動タイプ'] => ['魔法および忍術', '魔法和忍术'],
    [151, 'ステート特攻スキル'] => ['牙系スキル', '牙系技能'],
    [154, 'ステート特攻スキル'] => ['牙系スキル', '牙系技能'],
    [165, 'ステート特攻スキル'] => ['手淫系スキル', '手淫系技能'],
    [292, 'ステート特攻スキル'] => ['乳房系スキル', '乳房系技能'],
    [76, 'ステート特攻スキル'] => ['泡を使うスキル', '泡泡类技能'],
    [109, 'ステート特攻スキル'] => ['泡を使うスキル', '泡泡类技能'],
    [229, 'ステート特攻スキル'] => ['髪を使うスキル', '使用头发的技能'],
    [757, 'ステート特攻スキルタイプ'] => ['「刀技」「扇技」「陰陽術」「踊る」「淫技」', '「刀技」「扇技」「阴阳术」「舞蹈」「淫技」'],
    [749, 'ステート特攻スキルタイプ'] => ['扇技・闇技・踊る・歌う・造技', '扇技、暗技、舞蹈、歌唱、造技'],
    [790, 'スキルタイプ強化'] => ['全魔法', '所有魔法'],
    [818, 'スキルタイプ強化'] => ['魔法スキル', '魔法技能'],
    [251, '窮地スキル強化'] => ['乳房を使うスキル', '使用乳房的技能'],
    [27, 'MPスキル消費なし'] => ['聖属性スキル', '圣属性技能'],
    [28, 'MPスキル消費なし'] => ['聖属性スキル', '圣属性技能'],
    [29, 'MPスキル消費なし'] => ['聖属性スキル', '圣属性技能'],
    [30, 'MPスキル消費なし'] => ['聖属性スキル', '圣属性技能'],
    [883, 'TPスキル消費なし'] => ['乳房を使うスキル', '使用乳房的技能']
  }.freeze
  STATE_SCOPE_OVERRIDES = {
    23 => [[21] + PARAMETER_DOWN_EXTENDED_STATUS_IDS, ['消化・弱体状態', '消化及能力降低状态']],
    105 => [STUN_STATUS_IDS, ['スタン状態', '眩晕状态']],
    127 => [PARAMETER_DOWN_STATUS_IDS, ['弱体状態', '能力降低状态']],
    289 => [[23] + STUN_STATUS_IDS, ['ヌルヌル・スタン状態', '黏滑及眩晕状态']],
    382 => [[24, 25, 26, 27], ['快楽系状態異常', '快乐类异常状态']],
    395 => [[24, 25, 26, 27], ['快楽系状態異常', '快乐类异常状态']],
    492 => [[16, 17, 24, 25, 26, 27], ['スロウ・ストップ・快楽系状態異常', '减速、停止及快乐类异常状态']],
    629 => [ELEMENT_WEAKNESS_STATUS_IDS, ['属性弱体状態', '属性弱化状态']],
    637 => [ELEMENT_WEAKNESS_STATUS_IDS, ['属性弱体状態', '属性弱化状态']],
    641 => [[24, 25, 26, 27, 28], ['拘束・快楽系状態異常', '拘束及快乐类异常状态']],
    655 => [[25] + PARAMETER_DOWN_EXTENDED_STATUS_IDS, ['恍惚・弱体状態', '恍惚及能力降低状态']],
    656 => [PARAMETER_DOWN_EXTENDED_STATUS_IDS, ['弱体状態', '能力降低状态']],
    665 => [ELEMENT_WEAKNESS_STATUS_IDS, ['属性弱体状態', '属性弱化状态']],
    668 => [[7, 19] + ELEMENT_WEAKNESS_STATUS_IDS, ['毒・ゾンビ・属性弱体状態', '中毒、僵尸及属性弱化状态']],
    670 => [[16, 17] + ELEMENT_WEAKNESS_STATUS_IDS, ['スロウ・ストップ・属性弱体状態', '减速、停止及属性弱化状态']],
    738 => [[7, 8, 43], ['毒・暗闇・闇穢状態', '中毒、黑暗及暗秽状态']],
    739 => [[7, 8, 43], ['毒・暗闇・闇穢状態', '中毒、黑暗及暗秽状态']],
    757 => [[13, 42, 43], ['燃焼・聖痕・闇穢状態', '燃烧、圣痕及暗秽状态']],
    758 => [[14, 19, 43], ['凍結・ゾンビ・闇穢状態', '冻结、僵尸及暗秽状态']],
    877 => [ELEMENT_WEAKNESS_STATUS_IDS, ['属性弱体状態', '属性弱化状态']],
    897 => [[8, 9, 23, 28] + STUN_STATUS_IDS.drop(1), ['拘束・ヌルヌル・暗闇・沈黙・スタン状態', '拘束、黏滑、黑暗、沉默及眩晕状态']],
    907 => [[13] + ELEMENT_WEAKNESS_STATUS_IDS, ['燃焼・属性弱体状態', '燃烧及属性弱化状态']]
  }.freeze
  MANUAL_NAME_TRANSLATIONS = {
    '影紬' => '影䌷',
    '話す' => '交谈',
    'ロゴスマギア' => '逻各斯魔导器',
    'システム：シルフV2' => '系统：希尔芙V2',
    '神具XIII:ユダ' => '神具XIII:犹大',
    '特級神具IX:セントフレア' => '特级神具IX:圣焰',
    '発動：おっぱいビンタ' => '发动：胸部耳光',
    '発動：魅惑のマスコット' => '发动：魅惑吉祥物',
    '発動：加護の衣' => '发动：加护之衣',
    '遊ぶ：食料集め' => '玩耍：收集食物',
    'びっくり箱' => '惊吓箱',
    '悪夢の抱擁' => '恶梦的拥抱',
    '毒の息' => '毒息',
    '石化の魔眼' => '石化的魔眼',
    '反撃：カオスリタイド' => '反击：混沌撤退',
    '発動：燕返し' => '发动：燕返',
    '発動：意識共有化' => '发动：意识共享',
    '意識共有化' => '意识共享',
    'SP消費1/2' => 'SP消耗变为50%',
    '剣技二連続発動' => '剑技连续发动2次',
    '槍技二連続発動' => '枪技连续发动2次',
    '刀技二連続発動' => '刀技连续发动2次',
    '連続用：' => '连续用：',
    '発動：' => '发动：',
    '能力低下なし' => '无能力降低'
  }.freeze
  TRIGGER_STATE_DIRECT_EFFECTS = {
    165 => 'SP消耗变为50%',
    322 => '刀技连续发动2次',
    323 => '剑技连续发动2次',
    365 => '必中闪避率提升50%',
    324 => '枪技连续发动2次'
  }.freeze
  JAPANESE_RESIDUE_PATTERN = /[\p{Hiragana}\p{Katakana}]|反撃|連続|発動|消費|意識|状態|付与|剣|槍/.freeze
  # These database names are already valid Chinese and intentionally stay unchanged.
  UNCHANGED_CHINESE_NAMES = %w[
    阿吽 白蛇神光 被拘束 被永久拘束 虫技 触手技 催淫触手 毒 多武器技 防御 鬼神 海技 虎南
    黄金蜜 黄泉蜘蛛 恍惚 混乱 即死 拘束 巨技 雷属性弱点 量子 料理 猛毒触手 敏感 魔技
    魔精吸血 牛魔王 女神 群体核融合 溶解液 扇技 商技 蛇技 神舌乱舞 失禁 石化 手淫
    水属性弱点 睡眠 死神 四天光掌 特技 天上天下唯我独尊 土属性弱点 王技 物理
    物理属性弱点 吸血 消化 消化粘液 杏奈 虚牙 翼技 音波属性弱点 淫技 淫技・足舞
    影紬 永劫 勇者技 粘液技 植物技 重力 自爆 分裂 捕食 全体捕食 支援：花京淫 支援：管狐 ID 74技能类型（无对应技能类型）
  ].each_with_object({}) { |name, result| result[name] = name }.freeze

  class << self
    def run(root = File.expand_path('..', __dir__), output_dir = OUTPUT_DIR)
      @root = File.expand_path(root)
      @output_dir = File.expand_path(output_dir)
      @issues = []
      @missing_translations = {}
      FileUtils.mkdir_p(@output_dir)

      actors = load_database('Data/Actors.rvdata2')
      lookups = GouqiActorPassiveExplainer.load_lookups(@root)
      system = load_database('Data/System.rvdata2')
      lookups[:armor_types] = system.instance_variable_get(:@armor_types)
      lookups[:actors] = actors
      lookups[:classes] = load_database('Data/Classes.rvdata2')
      lookups[:items] = load_database('Data/Items.rvdata2')
      prepare_name_translations(lookups)

      rows = [[
        'actor_id', 'actor_name', 'ability_order', 'category', 'importance',
        'description_japanese', 'description_chinese', 'value_type', 'value_raw',
        'value_display', 'source', 'translation_status', 'original_text', 'source_raw',
        'comment_chinese'
      ]]

      actors.each_with_index do |actor, index|
        next unless actor
        actor_id = actor.instance_variable_get(:@id).to_i
        actor_id = index if actor_id.zero?
        actor_name = actor.instance_variable_get(:@name).to_s
        next if actor_name.empty?

        @current_actor_id = actor_id
        @current_actor_name = actor_name
        records = []
        extract_traits(actor, actor_id, actor_name, lookups, records)
        extract_notes(actor, actor_id, actor_name, lookups, records)
        append_actor_external_source_records(actor_id, lookups, records)
        append_actor_missing_source_raw_record(actor_id, records)
        annotate_duplicate_records(records)
        records.each_with_index do |record, order|
          @current_source_raw = record[:source_raw]
          audit_description_translation(record)
          rows << [actor_id, actor_name, order + 1, record[:category], record[:importance],
                   display_text(record[:jp]), display_text(record[:zh]), record[:value_type], record[:value_raw],
                   record[:value_display], record[:source], record[:translation_status],
                   record[:original_text], record[:source_raw], display_text(record[:comment])]
        end
      end

      write_csv('actor_important_abilities.csv', rows)
      write_csv('actor_important_ability_issues.csv',
                [['issue_type', 'actor_id', 'actor_name', 'source_raw', 'details']] + @issues)
      missing_rows = @missing_translations.keys.sort.map do |source_text|
        entry = @missing_translations[source_text]
        [source_text, entry[:count], entry[:actor_ids].join(','), entry[:actor_name], entry[:source_raw]]
      end
      write_csv('actor_important_ability_missing_translations.csv',
                [['source_text', 'occurrence_count', 'actor_ids', 'example_actor_name', 'example_source_raw']] + missing_rows)
      puts "Exported important ability records to #{@output_dir}"
      puts "Ability records: #{rows.length - 1}"
      puts "Issues recorded: #{@issues.length}"
      puts "Missing translations: #{@missing_translations.length}"
    end

    private

    def load_database(relative_path)
      path = File.join(@root, relative_path)
      abort("Database not found: #{path}") unless File.file?(path)
      GouqiActorPassiveExplainer.load_database(path)
    end

    def prepare_name_translations(lookups)
      @name_translations = GouqiActorPassiveExplainer::NAME_TRANSLATIONS
                                                        .merge(UNCHANGED_CHINESE_NAMES)
                                                        .merge(MANUAL_NAME_TRANSLATIONS)
      @source_translations = {}
      translation_path = Dir.glob(File.join(@root, '翻译', '*.json')).max_by { |path| File.mtime(path) }
      unless translation_path
        @name_translation_pattern = build_translation_pattern(@name_translations)
        return
      end

      translations = JSON.parse(File.binread(translation_path).force_encoding('UTF-8'))
      @source_translations = translations
      collections = [
        lookups[:skills], lookups[:states], lookups[:skill_types], lookups[:elements],
        lookups[:weapon_types], lookups[:armor_types], lookups[:classes], lookups[:actors]
      ]
      collections.compact.each do |collection|
        collection.compact.each do |item|
          name = database_name(item)
          translated = translations[name]
          @name_translations[name] = translated if translated && !name.empty? && translated != name
        end
      end
      @name_translation_pattern = build_translation_pattern(@name_translations)
    rescue JSON::ParserError, EncodingError => error
      @issues << ['translation_file_error', '', '', translation_path.to_s, error.message]
      @source_translations = {}
      @name_translation_pattern = build_translation_pattern(@name_translations)
    end

    def database_name(item)
      return item if item.is_a?(String)
      return item.name.to_s if item.respond_to?(:name)
      return item.instance_variable_get(:@name).to_s if item && item.instance_variable_defined?(:@name)
      ''
    end

    def build_translation_pattern(translations)
      names = translations.keys.reject(&:empty?).sort_by { |name| -name.length }
      names.empty? ? nil : Regexp.union(names)
    end

    def translate_chinese_text(text)
      value = text.to_s
      translated = if @name_translation_pattern
                     value.gsub(@name_translation_pattern) { |name| @name_translations.fetch(name, name) }
                   else
                     value
                   end
      normalize_chinese_text(translated)
    end

    def translate_name(text)
      value = text.to_s
      return value if value.match?(/\AID \d+.*（无对应[^）]*）\z/)

      translated = @source_translations[value] || @name_translations[value]
      return normalize_chinese_text(translated) unless translated.nil?

      translated = translate_chinese_text(value)
      register_missing_translation(value) if translated == value && value.match?(/[^\x00-\x7F]/)
      translated
    end

    # Use the established Chinese name for the poison abnormal state.
    # This is limited to state names so skill and item names remain unchanged.
    def state_name_zh(lookups, id)
      name = lookup(lookups[:states], id, '状态')
      normalize_state_name_zh(translate_name(name))
    end

    def normalize_state_name_zh(name)
      normalized = name.to_s == '毒' ? '中毒' : name.to_s
      normalized.gsub('万能闪避率', '必中闪避率').gsub('回避率', '闪避率')
    end

    def named_category_phrase(name, category, suffix)
      unknown = name.to_s.include?('（无对应') || name.to_s.include?('（対応不明')
      unknown ? "#{name}#{suffix}" : "#{name}#{category}#{suffix}"
    end

    def normalize_chinese_text(text)
      text.to_s
          .gsub('跳舞', '舞蹈')
          .gsub('二連続発動', '连续发动2次')
          .gsub('反撃：', '反击：')
          .gsub('意識共有化', '意识共享')
          .gsub('SP消費1/2', 'SP消耗变为50%')
          .gsub('发动发动：', '发动：')
    end

    def self_state_effect_zh(state_name)
      state_name.to_s
                 # State 148 is a next-turn extra-action effect, not battle turn 2.
                 .gsub('第二回合额外行动一次', '下一回合额外行动一次')
                 .gsub('第二回合额外行动+1', '下一回合额外行动+1')
                 .gsub(/(.+?)(?:提升|上升)\s*([+-]?\d+(?:\.\d+)?)%\z/, '\\1+\\2%')
    end

    def normalize_self_state_description(text)
      self_state_effect_zh(text)
    end

    # Keep the state 46 wording consistent with the other actor descriptions.
    def normalize_state_effect_description(text)
      text.to_s.gsub('回避率+50%', '闪避率提升50%').gsub('回避率提升', '闪避率提升')
    end

    def ex_category_names(category_id)
      id = category_id.to_i
      names = EX_CATEGORY_NAMES[id]
      return names if names

      register_missing_translation("种族ID #{id}")
      ["種族ID #{id}", "种族ID #{id}"]
    end

    def register_missing_translation(source_text)
      value = source_text.to_s
      return if value.empty?

      entry = (@missing_translations[value] ||= {
        :count => 0,
        :actor_ids => [],
        :actor_name => @current_actor_name.to_s,
        :source_raw => @current_source_raw.to_s
      })
      entry[:count] += 1
      actor_id = @current_actor_id.to_s
      entry[:actor_ids] << actor_id unless actor_id.empty? || entry[:actor_ids].include?(actor_id)
      entry[:actor_name] = @current_actor_name.to_s if entry[:actor_name].empty?
      entry[:source_raw] = @current_source_raw.to_s if entry[:source_raw].empty?
    end

    def audit_description_translation(record)
      text = record[:zh].to_s
      return unless text.match?(JAPANESE_RESIDUE_PATTERN)

      register_missing_translation(text)
    end

    def append_actor_external_source_records(actor_id, lookups, records)
      if actor_id == 75
        class_name = lookup(lookups[:classes], 92, '职业')
        source_raw = "其它来源：职业ID 92「#{class_name}」：<行動変化 28-50>"
        item = record(
          '行動変化',
          "#{class_name}职业的行动变化：50%の確率で技能ID 28を選択",
          "当前职业「#{class_name}」的行动变化：有50%概率选择技能ID 28",
          'chance', '50', '50%', 'other_source', source_raw
        )
        item[:comment] = '该行动变化来自当前职业ID 92「游人」，不是角色75自身的固有能力。角色图鉴提到她有时会无视命令喝酒；但此标签指定的是技能ID 28「遊ぶ」，与酒饮技能ID 3154不同，因此不能据此认定技能ID 28本身就是喝酒行为。角色75另在Lv1通过<固有習得 1-3154>习得技能ID 3154「酒飲み」（中文名「酒鬼」）；该技能会对使用者附加状态ID 71「酔拳」。获得「醉拳」是喝酒技能本身的通用状态效果，并非角色75独有。'
        records << item

        passive_name = skill_lookup(lookups[:skills], 873)
        drink_skill_name = skill_lookup(lookups[:skills], 3154)
        passive_source_raw = "其它来源：固有习得能力ID 873「#{passive_name}」→被动防具对象ID 6363：code=23, data_id=0, value=0.75；code=22, data_id=2, value=0.2；code=22, data_id=6, value=0.25；code=41, data_id=53, value=0.0；<行動変化 3154-10>"
        passive_item = record(
          '固有習得',
          "固有習得パッシブ能力「#{passive_name}」装備時、獣技を使用可能、攻撃対象に選ばれる重み×75%、会心率+20%、反撃率+25%；10%の確率で当ターンの行動を「#{drink_skill_name}」に変更",
          '装备固有习得被动能力「酒鬼羊」后，可以使用兽技；被选为攻击目标的权重变为75%；会心率 +20%、反击率 +25%；有10%概率将当回合行动替换为喝酒技能「酒鬼」',
          'composite', '53,75,20,25,3154-10', '', 'other_source', passive_source_raw
        )
        passive_item[:comment] = '角色75通过<固有習得 1-873>在Lv1习得被动能力ID 873「酒飲み羊」（酒鬼羊），但习得本身不代表能力已经装备。角色备注中的<初期アビリティ 3350>使用旧ID；旧ID替换表不会在解析角色备注时自动将其转换为873，因此需要手动装备能力873后上述效果才会生效。装备后，该能力引用的被动防具对象ID 6363会赋予兽技使用权限，使被选为攻击目标的权重变为75%、会心率提升20%、反击率提升25%，并有10%概率将当回合行动替换为技能ID 3154「酒飲み」。兽技使用权限不代表会自动学会具体兽技。'
        records << passive_item

        drunken_fist_source_raw = "其它来源：固有习得技能ID 3154「#{drink_skill_name}」→技能效果：状态ID 71「酔拳」100%"
        drunken_fist_item = record(
          '固有習得',
          "固有習得スキル「#{drink_skill_name}」使用時、自身に「酔拳」状態を付加（基本確率100%）",
          '使用固有习得技能「酒鬼」时，对自身附加「醉拳」状态（基础概率100%）',
          'chance', '71-100', '100%', 'other_source', drunken_fist_source_raw
        )
        drunken_fist_item[:comment] = '角色75在Lv1通过<固有習得 1-3154>习得技能ID 3154「酒飲み」（酒鬼）。该技能会附加状态ID 71「酔拳」；获得「醉拳」是喝酒技能本身的通用状态效果，并非角色75独有，因此不应标记为缺少source_raw。'
        records << drunken_fist_item
      elsif actor_id == 585
        ability_name = skill_lookup(lookups[:skills], 876)
        drink_skill_name = skill_lookup(lookups[:skills], 3154)
        source_raw = "其它来源：固有习得能力ID 876「#{ability_name}」→被动防具对象ID 6367：<行動変化 3154-10>"
        item = record(
          '行動変化',
          "固有習得パッシブ能力「#{ability_name}」装備時、10%の確率で当ターンの行動を「#{drink_skill_name}」に変更",
          '装备固有习得被动能力「醉醺醺的船长」后，有10%概率将当回合行动替换为喝酒技能「酒鬼」',
          'chance', '3154-10', '10%', 'other_source', source_raw
        )
        item[:comment] = '角色585通过<固有習得 1-876>在Lv1习得被动能力ID 876「酔いどれおかしら」（醉醺醺的船长），但习得本身不代表能力已经装备。角色备注中的<初期アビリティ 3353>使用旧ID；旧ID替换表不会在解析角色备注时自动将其转换为876，因此需要手动装备能力876后该行动变化才会生效。装备后，能力引用的被动防具对象ID 6367会以10%概率将当回合行动替换为技能ID 3154「酒飲み」（酒鬼）。该技能会对使用者附加状态ID 71「酔拳」；获得「醉拳」是喝酒技能本身的通用效果，并非角色585独有。与角色75的职业标签<行動変化 28-50>不同，后者指向「遊ぶ」而不是喝酒技能。'
        records << item

        pirate_name = skill_type_lookup(lookups[:skill_types], 32)
        permission_source_raw = "其它来源：固有习得能力ID 876「#{ability_name}」→被动防具对象ID 6367：code=41, data_id=32, value=0.0"
        permission_item = record(
          'skill',
          "固有習得パッシブ能力「#{ability_name}」装備時、「#{pirate_name}」を使用可能",
          '装备固有习得被动能力「醉醺醺的船长」后，可以使用海贼技',
          'boolean', '32', '', 'other_source', permission_source_raw
        )
        permission_item[:comment] = '角色585通过<固有習得 1-876>在Lv1习得被动能力ID 876「酔いどれおかしら」（醉醺醺的船长）。该能力引用被动防具对象ID 6367；装备后，对象的code=41、data_id=32特征会赋予海贼技使用权限，但不会自动学会具体海贼技。角色备注中的<初期アビリティ 3353>使用旧ID，无法自动装备当前能力876，因此需要手动装备后该效果才会生效。'
        records << permission_item

        boost_source_raw = "其它来源：固有习得能力ID 876「#{ability_name}」→被动防具对象ID 6367：<スキルタイプ強化 32-30>"
        boost_item = record(
          'skill_boost',
          "固有習得パッシブ能力「#{ability_name}」装備時、「#{pirate_name}」強化 +30%",
          '装备固有习得被动能力「醉醺醺的船长」后，海贼技强化 +30%',
          'additive_percent', '30', '+30%', 'other_source', boost_source_raw
        )
        boost_item[:comment] = '角色585的海贼技强化来自被动能力「酔いどれおかしら」（醉醺醺的船长）引用的被动防具对象ID 6367。装备能力后，对象备注<スキルタイプ強化 32-30>会使海贼技强化30%。角色备注中的<初期アビリティ 3353>使用旧ID，无法自动装备当前能力876，因此需要手动装备后该效果才会生效。'
        records << boost_item
      end
    end

    def append_actor_missing_source_raw_record(actor_id, records)
      descriptions = MISSING_SOURCE_RAW_DESCRIPTIONS[actor_id]
      return if descriptions.nil? || descriptions.empty?

      quoted_descriptions = descriptions.map { |description| "「#{description}」" }.join('；')
      extra_comment = MISSING_SOURCE_RAW_EXTRA_COMMENTS[actor_id].to_s
      records << {
        :category => 'missing_source_raw',
        :importance => 'core',
        :jp => '',
        :zh => '缺少对应source_raw的固有能力说明',
        :value_type => 'text',
        :value_raw => '',
        :value_display => '',
        :source => 'comparison',
        :translation_status => 'manual',
        :original_text => '',
        :source_raw => '缺少的source_raw',
        :comment => "当前未找到对应的source_raw：#{quoted_descriptions}。#{extra_comment}"
      }
    end

    def extract_traits(actor, actor_id, actor_name, lookups, records)
      features = actor.instance_variable_get(:@features) || []
      occurrences = Hash.new(0)
      features.each do |feature|
        code = feature.instance_variable_get(:@code).to_i
        data_id = feature.instance_variable_get(:@data_id)
        value = feature.instance_variable_get(:@value)
        @current_source_raw = "code=#{code}, data_id=#{data_id}, value=#{value}"
        skipped_default = default_trait_skip?(code, data_id, value) || equipment_trait_skip?(code, data_id, lookups)
        translated = IMPORTANT_TRAIT_CODES.include?(code) && !skipped_default
        jp = translated ? trait_text(code, data_id, value, lookups) : ''
        zh = translated ? translate_chinese_text(trait_text_zh(code, data_id, value, lookups)) : ''
        source_raw = "code=#{code}, data_id=#{data_id}, value=#{value}"
        occurrences[source_raw] += 1
        records << {
          :category => trait_category(code),
          :importance => skipped_default ? 'skipped' : (translated ? 'core' : 'unclassified'),
          :jp => jp,
          :zh => zh,
          :value_type => skipped_default ? 'skipped' : trait_value_type(code),
          :value_raw => value,
          :value_display => skipped_default ? '' : trait_value_display(code, value),
          :source => 'trait',
          :translation_status => skipped_default ? 'skipped_default' : (translated ? 'translated' : 'untranslated'),
          :original_text => jp,
          :source_raw => source_raw,
          :duplicate_occurrence => occurrences[source_raw],
          :comment => trait_comment(code, data_id, value, actor_id)
        }
      end
    end

    def extract_notes(actor, actor_id, actor_name, lookups, records)
      note = actor.instance_variable_get(:@note).to_s
      occurrences = Hash.new(0)
      note.each_line do |raw_line|
        line = raw_line.strip
        next if line.empty?
        occurrences[line] += 1
        occurrence = occurrences[line]
        @current_source_raw = line
        # Some source notes contain an extra leading '<' but are parsed by the game identically.
        parse_line = line.sub(/\A<<(?=[^>]+>\z)/, '<')
        match = parse_line.match(/\A<([^>]+)>\z/)
        unless match
          records << record_from_raw('', line)
          next
        end
        content = match[1].to_s
        tag = GouqiActorPassiveExplainer.tag_name(content)
        if actor_id == 143 && content == '初期アビリティ 3351'
          generated = [record(
            tag,
            '旧ID 3351はパッシブ能力ID 874「器用貧乏淫魔」に対応',
            '备注中的旧ID 3351对应当前被动能力ID 874「笨拙淫魔」',
            'ability', '3351', '旧ID 3351→能力ID 874', 'note', line, 'translated', 'core'
          )]
          generated.first[:comment] = '该标签使用旧ID 3351，对应当前被动能力874「器用貧乏淫魔」（笨拙淫魔）。旧ID替换表只用于迁移存档中已经存在的技能或能力，不会在解析角色备注时自动把该标签转换为当前能力。因此角色143虽然通过<固有習得 1-2490,1-874>学会能力874，但这条初期能力标签不会自动装备该能力，相关效果需要手动装备能力874后才会生效。'
          generated.first[:duplicate_occurrence] = occurrence
          records.concat(generated)
          next
        end
        if tag == '固有習得'
          intrinsic_summary = intrinsic_only_learning_summary(actor_id, content, lookups)
          if intrinsic_summary
            intrinsic_summary[:duplicate_occurrence] = occurrence
            records << intrinsic_summary
            next
          end
        end
        skip_reason = skip_reason_for_note(actor_id, tag, content)
        if skip_reason
          item = record(tag, '', '', 'skipped', '', '', 'note', line,
                        "skipped_#{skip_reason}", 'skipped')
          if actor_id == 861 && line == '<初期装備1,0:4825>'
            item[:comment] = '该标签的格式错误，游戏无法解析，会将其完全忽略。角色具备双持能力，且上一条标签已在主手装备武器ID 4825「エクゼキューショナー」；这里原本应写为<初期装備1:4825>，使副手也装备同一把武器。受此错误影响，角色初始状态的副手为空，实际少装备一把该武器，也无法获得第二把武器提供的属性、特征及插槽效果。'
          end
          item[:duplicate_occurrence] = occurrence
          records << item
          next
        end
        generated = explain_note_tag(actor_id, tag, content, lookups)
        if generated.empty?
          @issues << ['untranslated_note', actor_id, actor_name, line, "Unsupported tag: #{tag}"]
          generated << record_from_raw(tag, line)
        end
        generated = consolidate_note_records(generated)
        if tag == '固有習得' && [143, 611].include?(actor_id)
          summary = intrinsic_only_learning_summary(actor_id, content, lookups, false, true)
          if summary
            generated.first[:jp] = summary[:jp]
            generated.first[:zh] = summary[:zh]
            generated.first[:value_type] = summary[:value_type]
            generated.first[:value_raw] = summary[:value_raw]
            generated.first[:value_display] = summary[:value_display]
          end
        end
        append_record_comment(generated, ACTOR_NOTE_CORRECTIONS[[actor_id, line]])
        if line != parse_line
          append_record_comment(generated, '原备注多写了一个“<”，但是仍能正常生效。')
        end
        generated.each do |item|
          item[:source_raw] = line
          item[:original_text] = line if item[:source] == 'note'
          if actor_id == 657 && line == '<両手盾時能力:5210>'
            item[:jp] = '両手盾時に防具オブジェクトID 5210の特徴を有効化'
            item[:zh] = '双手盾时启用防具对象ID 5210的特征'
            item[:comment] = 'ID 5210指向防具对象而不是技能：该对象提供必中伤害率80%，并使投掷技计算攻击力时取攻击力与防御力中的较高值、计算灵巧时取灵巧与防御力中的较高值。双手盾时该对象会加入角色特征；它不会让角色获得或使用技能5210。'
          elsif actor_id == 657 && line == '<両手盾時能力:5212>'
            item[:jp] = '両手盾時に防具オブジェクトID 5212の特徴を有効化'
            item[:zh] = '双手盾时启用防具对象ID 5212的特征'
            item[:comment] = 'ID 5212指向防具对象而不是技能：该对象提供必中伤害率80%。双手盾时它会与能力对象5210同时加入角色特征，因此两个80%按相乘计算，必中攻击的最终伤害倍率为64%；它不会让角色获得或使用技能5212。'
          elsif actor_id == 485 && line == '<速攻発動スキルタイプ:31>' && occurrence == 2
            item[:comment] = '固有能力说明写的是“忍术连续发动两次”，但备注第二次重复的仍是“忍术速攻发动”；速攻效果不能叠加，因此这两条备注无法实现连续发动两次。作者很可能原本想写的是<連続発動タイプ 31-2>。'
          elsif actor_id == 4 && line == '<窮地スキルタイプ強化 7-200,26-200,27-200,48-200,70-200>' && item[:comment].to_s.empty?
            item[:comment] = '该备注中的勇者技（技能类型ID 48）与角色4另一条<窮地スキルタイプ強化 48-200>备注重复，另一条同样为+200%。游戏对同一技能类型的濒死强化取最高值，不会叠加，因此勇者技实际仍为濒死时强化+200%，不是+400%。'
          end
          if actor_id == 735 && line.include?('52-50')
            item[:comment] = '角色拥有粘液技使用权限，但初始状态没有学会任何粘液技技能，因此当前状态下没有可用的粘液技。'
          end
          if actor_id == 760 && line.start_with?('<スキルタイプ強化') && line.match?(/(?:19|43|60|70)-75/)
            item[:comment] = '该技能类型的+75%强化与同一角色另一条<スキルタイプ強化>标签中的同类+75%会叠加，因此铳技、器械、造技、混沌实际威力强化为+150%。'
          end
          item[:duplicate_occurrence] = occurrence
        end
        records.concat(generated)
      end
    end

    def intrinsic_only_learning_summary(actor_id, content, lookups, include_all = false, allow_special = false)
      return nil if !include_all && !allow_special && INTRINSIC_LEARNING_SPECIAL_ACTORS.include?(actor_id)

      pairs = content.sub(/\A固有習得\s*/, '').scan(/(\d+)\s*-\s*(\d+)/)
      selected = pairs.filter_map do |level, object_id|
        object_id = object_id.to_i
        intrinsic_only = INTRINSIC_ONLY_ABILITY_IDS.include?(object_id) || INTRINSIC_ONLY_SKILL_IDS.include?(object_id)
        next unless include_all || intrinsic_only

        skill = lookups[:skills] && lookups[:skills][object_id]
        next unless skill

        kind = INTRINSIC_ONLY_ABILITY_IDS.include?(object_id) ? :ability : :skill
        {
          level: level.to_i,
          object_id: object_id,
          kind: kind,
          jp_name: skill_lookup(lookups[:skills], object_id),
          zh_name: translate_name(skill_lookup(lookups[:skills], object_id))
        }
      end
      return nil if selected.empty?

      grouped = selected.group_by { |entry| entry[:level] }.sort_by(&:first)
      jp_parts = grouped.map { |level, entries| intrinsic_learning_group_text(level, entries, false) }
      zh_parts = grouped.map { |level, entries| intrinsic_learning_group_text(level, entries, true) }
      source_pairs = selected.map { |entry| "#{entry[:level]}-#{entry[:object_id]}" }
      item = record(
        '固有習得',
        jp_parts.join('；'),
        zh_parts.join('；'),
        'intrinsic_learning_summary',
        source_pairs.join(','),
        selected.map { |entry| entry[:object_id] }.join(','),
        'note',
        "<#{content}>"
      )
      item[:comment] = '本条仅列出角色专属固有习得的技能或能力。' unless include_all
      item
    end

    def intrinsic_learning_group_text(level, entries, chinese)
      skill_names = entries.select { |entry| entry[:kind] == :skill }
                          .map { |entry| chinese ? entry[:zh_name] : entry[:jp_name] }
      ability_names = entries.select { |entry| entry[:kind] == :ability }
                            .map { |entry| chinese ? entry[:zh_name] : entry[:jp_name] }
      skill_label = chinese ? '技能' : 'スキル'
      ability_label = chinese ? '能力' : 'アビリティ'
      parts = []
      parts << "#{skill_label}#{quoted_names(skill_names)}" unless skill_names.empty?
      parts << "#{ability_label}#{quoted_names(ability_names)}" unless ability_names.empty?
      text = parts.join(chinese ? '，' : '、')
      level == 1 ? (chinese ? "习得#{text}" : "#{text}を習得") : "Lv#{level}#{chinese ? '习得' : ''}#{text}#{chinese ? '' : 'を習得'}"
    end

    def quoted_names(names)
      names.map { |name| "「#{name}」" }.join('、')
    end

    # Keep one CSV record for one raw note while preserving every parsed effect.
    def consolidate_note_records(records)
      return records if records.length <= 1

      first = records.first
      descriptions_jp = records.map { |item| item[:jp].to_s }.reject(&:empty?).uniq
      descriptions_zh = records.map { |item| item[:zh].to_s }.reject(&:empty?).uniq
      comments = records.map { |item| item[:comment].to_s }.reject(&:empty?).uniq
      combined = first.dup
      combined[:jp] = descriptions_jp.join('；')
      combined[:zh] = descriptions_zh.join('；')
      combined[:value_type] = 'composite'
      combined[:value_raw] = records.map { |item| item[:value_raw].to_s }.reject(&:empty?).join('；')
      combined[:value_display] = ''
      combined[:comment] = comments.join('；')
      combined[:importance] = records.any? { |item| item[:importance].to_s == 'core' } ? 'core' : first[:importance]
      [combined]
    end

    def body_is_default_start_tp?(content, tag)
      body = content.sub(/\A#{Regexp.escape(tag)}\s*/, '').strip
      body.match?(/\A\+?50%\z/)
    end

    def skip_reason_for_note(actor_id, tag, content)
      metadata_tags = [
        'イラスト', '性別', '初期サブクラス', 'カテゴリー', '経験値曲線', '誘惑時使用スキル',
        '経験済職業', '初期アビリティ', '初期レベル', '表示ID', 'ナワバリ', '人間時追加特徴', '特殊カテゴリー',
        '主人格', '副人格', '図鑑除外'
      ]
      return 'metadata' if metadata_tags.include?(tag) || tag.start_with?('初期装備')
      return 'skill_mapping' if tag == 'スキル変化'
      return 'learned_skill' if tag == '固有習得' && ![143, 540, 542, 603, 611].include?(actor_id)
      body = content.sub(/\A#{Regexp.escape(tag)}\s*/, '').strip
      return 'default' if tag == 'TPLv補正' && body == '30'
      return 'default' if tag == 'TPLv100補正' && body == '30'
      return 'default' if tag == 'TP基本値' && body == '5'
      return 'default' if tag == '開始時TP' && body.match?(/\A\+?50%\z/)
      nil
    end

    def default_trait_skip?(code, data_id, value)
      return true if code == 41 && data_id.to_i == 63 && value.to_f == 0.0
      return true if code == 22 && data_id.to_i == 1 && (value.to_f - 0.05).abs < 0.000001
      return true if code == 22 && data_id.to_i == 2 && (value.to_f - 0.05).abs < 0.000001
      return true if code == 23 && data_id.to_i == 0 && (value.to_f - 1.0).abs < 0.000001
      false
    end

    def equipment_trait_skip?(code, data_id, lookups)
      collection = code == 51 ? lookups[:weapon_types] : (code == 52 ? lookups[:armor_types] : nil)
      return false unless collection
      %w[混沌 アクセサリ].include?(collection[data_id.to_i].to_s)
    end

    def explain_note_tag(actor_id, tag, content, lookups)
      direct_percent_labels = DIRECT_PERCENT_NOTE_LABELS[tag]
      if direct_percent_labels
        value = content[/[+-]?\d+(?:\.\d+)?/]
        return [] unless value

        display = "+#{value}%"
        return [record(tag, "#{direct_percent_labels[0]} #{display}",
                       "#{direct_percent_labels[1]} #{display}",
                       'additive_percent', value, display, 'note', "<#{content}>")]
      end

      body = content.sub(/\A#{Regexp.escape(tag)}\s*/, '').strip
      body, overwrite_comment = normalize_hash_pair_note(tag, body, lookups)
      if tag == '能力値置き換え'
        parsed = parse_stat_replacement(body)
        return [] unless parsed

        stype_ids, source_id, replacement_id = parsed
        stype_jp = skill_type_names(stype_ids, lookups, false)
        stype_zh = skill_type_names(stype_ids, lookups, true)
        source_jp, source_zh = ability_value_names(source_id)
        replacement_jp, replacement_zh = ability_value_names(replacement_id)
        jp = "#{stype_jp}の#{source_jp}計算は、#{source_jp}と#{replacement_jp}の高い方を使用"
        zh = "#{stype_zh}计算#{source_zh}时，取#{source_zh}与#{replacement_zh}中的较高值"
        display = "技能类型ID #{stype_ids.join(',')}：#{source_zh}与#{replacement_zh}取较高值"
        item = record(tag, jp, zh, 'stat_reference', body, display, 'note', "<#{content}>")
        if [163, 836].include?(actor_id) && stype_ids == [52] && source_id == 6 && replacement_id == 3
          item[:comment] = '固有能力描述写成「触手技」的威力改为取决于魔力而非灵巧，但原始备注实际作用于「粘液技」：计算灵巧时取灵巧与魔力中的较高值，两者不符。角色的种族本身拥有粘液技使用权限，但初始状态没有学会任何粘液技技能，因此当前没有可用的粘液技。'
        elsif actor_id == 493 && stype_ids == [15]
          item[:comment] = '原始备注指定的是「鞭技」（技能类型ID 15），但同一组固有能力中的其他相关标签均作用于「弓技」（技能类型ID 14），因此很可能是作者误将14写成了15。角色已通过职业获得鞭技使用权限，但初始状态没有学会任何鞭技技能，因此当前没有可用的鞭技。'
         elsif actor_id == 845 && stype_ids == [11] && source_id == 1 && replacement_id == 4
           item[:comment] = '固有能力描述中包含「棍技」的相关效果，但原始备注实际写成了「斧技计算攻击力时，取攻击力与精神力中的较高值」（技能类型ID 11）；角色本身不能使用斧技，该效果对角色本身无效。作者原本想写的应是「棍技」（技能类型ID 12），可能误将12写成了11。'
          elsif actor_id == 999 && stype_ids == [30] && source_id == 3 && replacement_id == 6
            item[:comment] = '固有能力描述写的是「圣技」「暗技」「混沌」的威力取决于灵巧，但原始备注实际将能力值替换配置给了盗贼技（技能类型ID 30），没有配置圣技（26）、暗技（27）或混沌（70）。因此混沌无法获得描述中的灵巧替换效果，盗贼技则获得了一个与固有能力描述不符的替换效果。作者很可能误将混沌（技能类型ID 70）写成了盗贼技（技能类型ID 30）。角色本身不能使用盗贼技，因此该盗贼技替换效果对角色本身也不生效。'
          elsif actor_id == 706 && stype_ids == [30] && source_id == 3 && replacement_id == 6
            item[:comment] = '这条记录来自角色备注中的底层标签<能力値置き換え 30,3,6>，并非固有能力说明所写的效果；角色自身特性也未授予盗贼技使用权限，因此应视为底层遗留标签，而不是固有能力文案错误。数据库中现有的18个盗贼技技能，其伤害公式都不使用魔力。即使角色从其他来源获得盗贼技使用权限，这条标签也不会让盗贼技伤害按魔力计算。'
          elsif actor_id == 678 && stype_ids == [60] && source_id == 3 && replacement_id == 6
            item[:comment] = '固有能力描述为「格斗」「自然感应」的威力取决于灵巧，但原始备注实际指定的是「造技」计算魔力时取魔力与灵巧中的较高值；因此「自然感应」取决于灵巧的效果不生效，且角色本身不能使用造技。'
          elsif [397, 398, 399, 400].include?(actor_id) && stype_ids == [60] && source_id == 1 && replacement_id == 6
            item[:comment] = '固有能力描述写成「造技」的威力取决于敏捷，但原始备注<能力値置き換え 60,1,6>实际效果是造技计算攻击力时，取攻击力与灵巧中的较高值。两者不一致；能力值ID 5为敏捷、ID 6为灵巧，因此很可能是作者误将5写成了6。当前应以原始备注的实际效果为准。'
          end
        return [item]
      end
      if tag == 'スキルチェーン'
        ids = body.scan(/\d+/).map(&:to_i)
        return [] if ids.empty?
        names_jp = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
        names_zh = names_jp.map { |name| translate_name(name) }
        item = record(tag, "#{names_jp.join('→')}スキルチェーン", "#{names_zh.join('→')}技能链", 'id_list', ids.join(','), '', 'note', "<#{content}>")
        if actor_id == 479 && ids == [11, 59, 62]
          item[:comment] = '固有能力说明写成「吐息」之后可以连锁发动「斧技」，但原始备注实际指定的是「斧技→尸技→吐息」三段技能链；因此当前备注并不是“吐息→斧技”的两段链。'
        elsif actor_id == 493 && ids == [26, 15, 25]
          item[:comment] = '原始备注指定技能链为「圣技→鞭技→召唤术」，但同一组固有能力中的其他相关标签均作用于弓技，因此很可能是作者误将技能类型ID 14（弓技）写成了15（鞭技）。角色已通过职业获得鞭技使用权限，但初始状态没有学会任何鞭技技能，因此当前无法完整发动该技能链。'
        elsif actor_id == 752 && ids == [17, 54, 27]
          item[:comment] = '固有能力描述写成「暗技或尸技」「蛇技」「铁球技」可按顺序连锁发动，但原始备注实际指定的是「铁球技→蛇技→暗技」。角色已通过拉米亚系种族获得蛇技使用权限，并已学会多项蛇技；铁球技和暗技也可以使用，因此该技能链可以正常发动。'
        elsif actor_id == 752 && ids == [58, 54, 27]
          item[:comment] = '固有能力描述写成「暗技或尸技」「蛇技」「铁球技」可按顺序连锁发动，但原始备注实际还指定了一条「植物技→蛇技→暗技」技能链。角色本身不能使用植物技，因此无法用植物技发动这条技能链；蛇技和暗技本身可以使用。'
        end
        return [item]
      end
      summary = summarize_long_note(actor_id, tag, body, lookups, content)
      if summary && !summary.empty?
        append_record_comment(summary, overwrite_comment)
        return summary
      end

      case tag
      when 'スキルタイプ強化', '属性強化'
        pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
        return [] if pairs.empty?
        collection = tag == '属性強化' ? lookups[:elements] : lookups[:skill_types]
        fallback = tag == '属性強化' ? '属性' : '技能类型'
        records = pairs.map do |id, amount|
          name_jp = tag == '属性強化' ? element_lookup(collection, id) : skill_type_lookup(collection, id)
          name_zh = translate_name(name_jp)
          if tag == '属性強化'
            jp = "#{named_category_phrase(name_jp, '属性', '強化')} +#{amount}%"
            zh = id == '38' ? "恢复属性技能的恢复量 +#{amount}%" : "#{named_category_phrase(name_zh, '属性', '强化')} +#{amount}%"
          else
            jp = "#{name_jp}強化 +#{amount}%"
            zh = "#{name_zh}强化 +#{amount}%"
          end
          item = record(tag, jp, zh,
                        'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
          if actor_id == 627 && tag == '属性強化' && id == '68' && amount == '50'
            item[:comment] = '固有能力说明写成「魔技」「妖术」威力大幅提升，但原始备注误用了属性强化标签<属性強化 50-50,68-50>。技能类型ID 50「魔技」被当作属性ID后，实际变成终焉属性威力 +50%；技能类型ID 68「妖术」没有对应的属性ID，因此68-50无法作为属性强化生效。结果是魔技和妖术的技能威力强化均未生效。'
          elsif actor_id == 398 && tag == '属性強化' && id == '41' && amount == '50'
            item[:comment] = '固有能力描述写的是物理、重力属性攻击威力提升，但原始备注<属性強化 1-50,41-50>实际指定了物理属性（ID 1）和银河属性（ID 41）。因此银河属性这一项与固有能力描述不一致，很可能是作者将重力属性ID 40误写成了银河属性ID 41；当前应以原始备注的实际效果为准。'
          elsif actor_id == 845 && tag == '属性強化' && %w[49 50].include?(id) && amount == '10'
            item[:comment] = '原始备注为<属性強化 10-49,10-50>，当前实际解析为暗属性强化49%与暗属性强化50%；这与固有能力描述中的永劫、终焉属性强化不符。作者可能原本想写永劫属性强化50%与终焉属性强化50%，但该推测需以原始数据或实测为准。'
          elsif actor_id == 760 && tag == 'スキルタイプ強化' && %w[19 43 60 70].include?(id) && amount == '75'
            item[:comment] = '该技能类型的+75%强化与同一角色另一条<スキルタイプ強化>标签中的同类+75%会叠加，因此铳技、器械、造技、混沌实际威力强化为+150%。'
          end
          item
        end
        append_record_comment(records, overwrite_comment)
        return records
      when 'ステート割合強化タイプ'
        pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |stype_id, amount|
          name_jp = skill_type_lookup(lookups[:skill_types], stype_id)
          name_zh = skill_type_effect_name_zh(lookups[:skill_types], stype_id)
          record(tag, "#{name_jp}のステート付与率#{percent_change_phrase_jp(amount)}",
                 "#{name_zh}的状态附加率#{percent_change_phrase_zh(amount)}",
                 'additive_percent', amount, "#{signed_number(amount.to_f)}%", 'note', "<#{content}>")
        end
      when 'スキル強化', 'ステート割合強化スキル'
        pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |skill_id, amount|
          skill = skill_lookup(lookups[:skills], skill_id)
          skill_zh = translate_name(skill)
          if tag == 'スキル強化'
            record(tag, "#{skill}の威力 +#{amount}%", "#{skill_zh}威力 +#{amount}%",
                   'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
          else
            record(tag, "#{skill}の状態異常付加率 +#{amount}%", "#{skill_zh}的异常状态附加率 +#{amount}%",
                   'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
          end
        end
      when 'スキル変化'
        pairs = body.scan(/(\d+)\s*-\s*(\d+)/)
        return [] if pairs.empty?
        return pairs.map do |old_id, new_id|
          old_name = skill_lookup(lookups[:skills], old_id)
          new_name = skill_lookup(lookups[:skills], new_id)
          record(tag, "#{old_name}→#{new_name}に変化", "#{old_name}→#{new_name}变化", 'id_pair', "#{old_id}-#{new_id}", '', 'note', "<#{content}>")
        end
      when '特殊カテゴリー'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        return [record(tag, "特殊カテゴリーID：#{ids.join(',')}", "种族ID：#{ids.join(',')}", 'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when '人間時追加特徴'
        id = body[/\d+/]
        return [] unless id
        name = lookup(lookups[:classes], id, '职业/特性')
        return [record(tag, "人間時に追加特徴：#{name}", "人类形态时追加特性：#{name}", 'id', id, '', 'note', "<#{content}>")]
      when '固有習得'
        pairs = body.scan(/(\d+)\s*-\s*(\d+)/)
        return [] if pairs.empty?
        return pairs.map do |level, skill_id|
          name = skill_lookup(lookups[:skills], skill_id)
          item = record(tag, "Lv#{level}で#{name}を習得", "Lv#{level}习得#{name}", 'id_pair', "#{level}-#{skill_id}", '', 'note', "<#{content}>")
          if actor_id == 143 && level == '1' && skill_id == '874'
            item[:jp] = 'アビリティ「器用貧乏淫魔」を習得'
            item[:zh] = '习得能力「笨拙淫魔」'
            item[:comment] = '该标签表示角色在Lv1学会被动能力ID 874「器用貧乏淫魔」（笨拙淫魔）；习得本身不代表能力已经装备。角色备注中的<初期アビリティ 3351>使用旧ID，旧ID替换表不会在解析角色备注时自动将其转换为当前能力874「器用貧乏淫魔」（笨拙淫魔），因此角色143不会自动装备能力874，相关效果需要手动装备后才会生效。装备后，能力引用的被动防具对象ID 6364会赋予盗贼技、商技、神谕、舞蹈、歌唱、交谈、料理、医术、侍奉和淫技的使用权限，但不会强化这些技能。该对象还提供三个行动变化候选：技能ID 1993「命运塔罗牌」和技能ID 1995「老虎机」的单次判定概率各为10%，技能ID 1989「抛硬币」的单次判定概率为3%。游戏会在每次行动变化判定时随机打乱候选顺序，并逐项判定，触发其中一项后停止；三者至少触发一项的总概率约为21.43%，但各技能最终发动的概率会受随机顺序影响。因此，“战斗中有时会擅自使用神谕技”的效果只有在装备能力874后才会生效。'
          elsif actor_id == 542 && level == '1' && skill_id == '875'
            item[:jp] = 'アビリティ「残念なマーメイド」を習得'
            item[:zh] = '习得能力「残念的人鱼」'
            item[:comment] = '该标签表示角色在Lv1学会被动能力ID 875「残念なマーメイド」（残念的人鱼），但习得本身不代表能力已经装备或立即生效。装备后，能力引用的被动防具对象ID 6366会赋予海技使用权限，使所有技能的金币消耗量变为50%（并非只按「商技」类型判断）、被选为攻击目标的权重变为25%，并有3%概率将当回合行动替换为技能ID 3303「遊ぶ：強制死亡」。海技使用权限不代表会自动学会具体海技。角色备注中的<初期アビリティ 3352>使用旧ID；旧ID替换表不会在解析角色备注时自动将其转换为875，因此需要手动装备能力875后上述效果才会生效。'
          elsif actor_id == 540 && level == '1' && skill_id == '424'
            item[:jp] = 'アビリティ「口先八丁」を習得'
            item[:zh] = '习得能力「能言善辩」'
            item[:comment] = '该标签使角色在Lv1学会被动能力ID 424「口先八丁」（能言善辩），但该能力也可由职业ID 122「話神」在Lv6习得，因此不属于只能由该角色获得的专属能力。习得本身不代表能力已经装备或立即生效。装备后，能力引用的被动防具对象ID 1739「話術縛符」会使交谈以外的技能类型全部被封印，并使交谈SP消耗量变为50%（减少50%）、闪避率和魔法闪避率各提升30%。角色540没有<初期アビリティ>标签，需要手动装备该能力后上述效果才会生效。'
          elsif actor_id == 611 && level == '1' && skill_id == '880'
            item[:jp] = 'アビリティ「出世貧乏淫魔」を習得'
            item[:zh] = '习得能力「出人头地的淫魔」'
            item[:comment] = '该标签表示角色在Lv1学会被动能力ID 880「出世貧乏淫魔」（出人头地的淫魔），但习得本身不代表能力已经装备或立即生效。装备后，能力引用的被动防具对象ID 6365会赋予盗贼技、商技、神谕、舞蹈、歌唱、交谈、料理、医术、侍奉、王技和淫技的使用权限，并使这些技能类型强化30%。该对象还提供三个行动变化候选：技能ID 1993「命运塔罗牌」和技能ID 1995「老虎机」的单次判定概率各为10%，技能ID 1989「抛硬币」的单次判定概率为3%。游戏会在每次行动变化判定时随机打乱候选顺序，并逐项判定，触发其中一项后停止；三者至少触发一项的总概率约为21.43%，但各技能最终发动的概率会受随机顺序影响。角色备注中的<初期アビリティ 3351>使用旧ID；旧ID替换表不会在解析角色备注时自动将其转换为能力874「器用貧乏淫魔」（笨拙淫魔）或能力880「出世貧乏淫魔」（出人头地的淫魔）。即使只看旧ID替换关系，3351对应的也是能力874「器用貧乏淫魔」（笨拙淫魔），而不是能力880「出世貧乏淫魔」（出人头地的淫魔）。角色需要手动装备能力880后上述效果才会生效；这是初期能力ID配置错误，并非<行動変化>机制失效。此外，角色备注将能力880写入两条<固有習得>标签，但重复习得不会使效果叠加。'
          end
          item
        end
      when 'ステート特攻スキルタイプ', 'ステート特攻スキル'
        triples = body.scan(/(\d+)-(\d+)-([+-]?\d+)/)
        return [] if triples.empty?
        return triples.map do |first, state_id, amount|
          target = tag == 'ステート特攻スキルタイプ' ? skill_type_lookup(lookups[:skill_types], first) : skill_lookup(lookups[:skills], first)
          state = lookup(lookups[:states], state_id, '状态')
          display = "+#{amount}%"
          zh_target = translate_name(target)
          state_zh = normalize_state_name_zh(translate_name(state))
          item = record(tag, "#{target}对#{state}特攻 #{display}", "#{zh_target.empty? ? target : zh_target}对#{state_zh}的特攻伤害 #{display}", 'additive_percent', amount, display, 'note', "<#{content}>")
          if actor_id == 183 && tag == 'ステート特攻スキルタイプ' && first == '58' && state_id == '28' && amount == '100'
            item[:comment] = '固有能力描述写成对拘束状态的敌人使用「触手技」可造成特攻伤害，但原始备注实际指定的是「植物技对拘束特攻伤害 +100%」，两者不符。角色已通过职业获得植物技使用权限，但初始状态没有学会任何植物技技能，因此当前没有可用的植物技。'
          elsif actor_id == 864 && tag == 'ステート特攻スキルタイプ' && first == '69' && state_id == '23' && amount == '100'
            item[:comment] = '该「巨技对黏滑特攻 +100%」与同一角色另一条「巨技对黏滑特攻 +150%」会相加，合计特攻增幅为 +250%，对应特攻倍率为 ×3.5。'
          elsif actor_id == 636 && tag == 'ステート特攻スキルタイプ' && first == '8' && state_id == '13' && amount == '150'
            item[:comment] = '固有能力描述写成对燃烧、冻结、电击状态的敌人使用「尖剑」可造成大量特攻伤害，但原始备注实际仅指定尖剑技、刀技、枪技对燃烧的特攻伤害 +150%。角色已通过职业获得刀技使用权限，但初始状态没有学会任何刀技技能，因此当前没有可用的刀技；角色本身不能使用枪技。因此当前只有尖剑技部分可以发挥。'
          end
          item
        end
      when 'パーティ特定アクター能力アップ'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        owner_actor_id = actor_id
        return pairs.map do |actor_id, amount|
          target_id = actor_id
          name = lookup(lookups[:actors], target_id, '角色')
          name_zh = actor_name_chinese(lookups[:actors], target_id)
          display = "+#{amount}%"
          target_zh = owner_actor_id == 60 ? '兽族伙伴' : name_zh
          item = record(tag, "#{name}がパーティにいる時、能力 #{display}", "#{target_zh}在队伍中时能力强化 #{display}#{PARTY_ACTOR_ABILITY_SUFFIX}", 'additive_percent', amount, display, 'note', "<#{content}>")
          if owner_actor_id == 60
            item[:comment] = "对应角色：#{id_name_entry(target_id, lookups[:actors], '角色')}"
          end
          item
        end
      when '連続発動タイプ', '連続発動スキル'
        if tag == '連続発動タイプ'
          malformed = malformed_repeat_type_record(body, lookups, content)
          return [malformed] if malformed
        end
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |id, count|
          name = tag == '連続発動タイプ' ? skill_type_lookup(lookups[:skill_types], id) : skill_lookup(lookups[:skills], id)
          record(tag, "#{name}连续发动#{count}次", "#{name}连续发动#{count}次", 'count', count, "#{count}次", 'note', "<#{content}>")
        end
      when 'スキルタイプステート敵付加', 'スキルタイプステート味方付加', 'スキルタイプステート自己付加'
        triples = body.scan(/(\d+)-(\d+)-([+-]?\d+)/)
        return [] if triples.empty?
        return triples.map do |skill_id, state_id, amount|
          target = skill_type_lookup(lookups[:skill_types], skill_id)
          target_zh = translate_name(target)
          state = lookup(lookups[:states], state_id, '状态')
          state_zh = state_name_zh(lookups, state_id)
          if tag.include?('自己')
            jp = "#{target}使用時、自身に「#{state}」効果を#{amount}%の確率で付与"
            zh = "使用#{target_zh}时，以#{amount}%概率赋予自身「#{self_state_effect_zh(state_zh)}」效果"
          else
            subject_jp = tag.include?('敵') ? '敵' : '味方'
            subject_zh = tag.include?('敵') ? '对敌人' : '为队友'
            jp = "#{target}使用時、#{subject_jp}に「#{state}」を#{amount}%の確率で付与"
            zh = "使用#{target_zh}时，以#{amount}%概率#{subject_zh}附加「#{state_zh}」状态"
          end
          item = record(tag, jp, normalize_state_effect_description(zh), 'chance', amount, "#{amount}%", 'note', "<#{content}>")
          item[:zh] = normalize_self_state_description(item[:zh]) if tag.include?('自己')
          if actor_id == 126 && tag == 'スキルタイプステート敵付加' && skill_id == '21' && state_id == '393' && amount == '60'
            item[:comment] = '固有能力描述写成「造技」有几率使敌人陷入攻击力下降状态，但原始备注实际指定的是使用「格斗」时，以60%概率对敌人附加「攻击力下降」状态，两者不符；角色本身不能使用格斗。'
          elsif actor_id == 804 && tag == 'スキルタイプステート敵付加' && skill_id == '24' && state_id == '24' && amount == '30'
            item[:comment] = '固有能力描述写成使用「弓技」使敌人频繁陷入敏感状态，但原始备注实际指定的是使用「时魔法」时，以30%概率对敌人附加「敏感」状态；角色本身不能使用时魔法，因此该效果当前无法发挥。结合固有能力描述以及相邻标签均以弓技（技能类型ID 14）为对象，作者很可能将应写的14-24-30误写成了24-24-30，即误将技能类型ID也写成了敏感状态的ID 24。'
          elsif actor_id == 195 && tag == 'スキルタイプステート敵付加' && skill_id == '23' && state_id == '26' && amount == '30'
            item[:comment] = '固有能力描述写成「黑魔法」有几率使敌人陷入「敏感」状态，但原始备注实际指定的是使用黑魔法时，以30%概率对敌人附加「诱惑」状态（状态ID 26）；这里应以原始备注解析结果为准，并非敏感状态。'
          end
          item[:zh] = normalize_state_effect_description(item[:zh])
          item
        end
      when 'スキルステート付加', 'スキルステート自己付加'
        triples = body.scan(/(\d+)-(\d+)-([+-]?\d+)/)
        return [] if triples.empty?
        self_target = tag.include?('自己')
        subject_jp = self_target ? '自身' : (actor_id == 451 ? '蘇生対象' : 'スキル対象')
        subject_zh = self_target ? '自身' : (actor_id == 451 ? '复活目标' : '技能目标')
        grouped = triples.group_by { |_skill_id, state_id, amount| [state_id, amount] }
        jp_parts = []
        zh_parts = []
        grouped.each do |(state_id, amount), entries|
          skill_names = entries.map { |skill_id, _state, _amount| skill_lookup(lookups[:skills], skill_id) }
          skill_names_zh = skill_names.map { |name| translate_name(name) }
          state_name = lookup(lookups[:states], state_id, '状态')
          state_name_zh = state_name_zh(lookups, state_id)
          if self_target
            jp_parts << "#{skill_names.join('、')}使用時、自身に「#{state_name}」効果を#{amount}%の確率で付与"
            zh_parts << "使用#{skill_names_zh.join('、')}时，以#{amount}%概率赋予自身「#{self_state_effect_zh(state_name_zh)}」效果"
          else
            jp_parts << "#{skill_names.join('、')}使用時、#{subject_jp}に「#{state_name}」を#{amount}%の確率で付与"
            zh_parts << "使用#{skill_names_zh.join('、')}时，以#{amount}%概率对#{subject_zh}附加「#{state_name_zh}」状态"
          end
        end
        uniform = grouped.values.flatten(1).map { |_skill_id, _state_id, amount| amount }.uniq.length == 1
        amount = triples.first[2]
        value_type = uniform ? 'chance' : 'mapping'
        value_raw = uniform ? amount : triples.map { |skill_id, state_id, value| "#{skill_id}-#{state_id}-#{value}" }.join(',')
        value_display = uniform ? "+#{amount}%" : ''
        item = record(tag, jp_parts.join('；'), zh_parts.join('；'), value_type, value_raw, value_display, 'note', "<#{content}>")
        item[:zh] = normalize_self_state_description(item[:zh]) if self_target
        item[:comment] = state_effect_comment(tag, triples, lookups) if grouped.length > 1 || item[:zh].length > INLINE_DESCRIPTION_LIMIT
        [item]
      when '窮地スキルタイプ強化', '窮地スキル強化'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |id, amount|
          name = tag.include?('タイプ') ? skill_type_lookup(lookups[:skill_types], id) : skill_lookup(lookups[:skills], id)
          name_zh = translate_name(name)
          if name.start_with?('発動：') || name_zh.start_with?('发动：')
            jp = "瀕死時、スキル「#{name}」の威力 +#{amount}%"
            zh = "濒死时，技能「#{name_zh}」的威力 +#{amount}%"
          else
            jp = "瀕死時#{name}強化 +#{amount}%"
            zh = "濒死时#{name_zh}强化 +#{amount}%"
          end
          item = record(tag, jp, zh, 'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
          if actor_id == 267 && tag == '窮地スキルタイプ強化' && id == '30' && amount == '100'
            item[:comment] = '游戏中的固有能力说明写成伴随HP减少「刀技」得到强化，但原始备注实际指定的是濒死时「盗贼技」强化 +100%，两者不符。角色本身不能使用盗贼技，因此该强化当前无法发挥。'
          elsif actor_id == 4 && tag == '窮地スキルタイプ強化' && id == '48' && amount == '200'
            item[:comment] = '角色4的另一条<窮地スキルタイプ強化>备注也包含勇者技（技能类型ID 48）+200%。游戏对同一技能类型的濒死强化取最高值，不会叠加，因此勇者技实际仍为濒死时强化+200%，不是+400%。'
          end
          item
        end
      when '頑強スキルタイプ', '頑強スキル', '速攻発動スキルタイプ', '速攻発動スキル'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        fast = tag.start_with?('速攻')
        type = tag.include?('タイプ')
        names = ids.map { |id| type ? skill_type_lookup(lookups[:skill_types], id) : skill_lookup(lookups[:skills], id) }
        jp = fast ? "#{names.join('、')}速攻发动" : "#{names.join('、')}顽强发动"
        zh = fast ? "#{names.join('、')}速攻发动" : "#{names.join('、')}顽强发动"
        return [record(tag, jp, zh, 'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when '通常攻撃'
        id = body[/\d+/]
        return [] unless id
        name = skill_lookup(lookups[:skills], id)
        return [record(tag, "通常攻撃：#{name}", "普通攻击：#{name}", 'id', id, '', 'note', "<#{content}>")]
      when '会心ダメージ増加', '魔法会心率', '拡張会心率', '必中回避率', '拡張必中回避率', '拡張回避率', '拡張魔法回避率', '物理反射率', '拡張物理反射率', '必中反射率', '魔法反撃率', '必中反撃率', '必中反撃', '魔法反撃'
        value = body[/[+-]?\d+/]
        return [] unless value
        label_zh = { '会心ダメージ増加' => '会心伤害增加', '魔法会心率' => '魔法会心率', '拡張会心率' => '会心率', '必中回避率' => '必中闪避率', '拡張必中回避率' => '必中闪避率', '拡張回避率' => '闪避率', '拡張魔法回避率' => '魔法闪避率', '物理反射率' => '物理反射率', '拡張物理反射率' => '物理反射率', '必中反射率' => '必中反射率', '魔法反撃率' => '魔法反击率', '必中反撃率' => '必中反击率', '必中反撃' => '必中反击', '魔法反撃' => '魔法反击' }[tag]
        display = "+#{value}%"
        item = record(tag, "#{tag} #{display}", "#{label_zh} #{display}", 'additive_percent', value, display, 'note', "<#{content}>")
        if actor_id == 534 && tag == '拡張回避率' && value.to_f == 15.0
          item[:comment] = '固有能力说明写有敏捷和回避率大幅提升，但角色534及其关联角色533的底层数据库特征中都没有提升敏捷的参数特征（特征码21），角色534的备注也没有敏捷强化标签。当前仅有<拡張回避率 15%>，实际效果是回避率提升15%；这不是提取器漏掉了敏捷特征，而是固有能力说明与数据库中的实际效果不符。'
        end
        [item]
      when 'MP満タン威力アップスキルタイプ', 'SP満タン威力アップスキルタイプ'
        pair = body.match(/(\d+)\s*,\s*([+-]?\d+)/)
        return [] unless pair
        name = skill_type_lookup(lookups[:skill_types], pair[1])
        item = record(tag, "#{name}满#{tag.start_with?('MP') ? 'MP' : 'SP'}时威力 +#{pair[2]}%", "#{name}满#{tag.start_with?('MP') ? 'MP' : 'SP'}时威力 +#{pair[2]}%", 'additive_percent', pair[2], "+#{pair[2]}%", 'note', "<#{content}>")
        if actor_id == 612 && tag == 'MP満タン威力アップスキルタイプ' && pair[1] == '22'
          item[:comment] = '固有能力描述概括为MP剩余量越多，魔法和妖术威力越高；原始备注实际为白魔法、黑魔法、时魔法、召唤术、圣技、暗技、魔法剑、阴阳术、念动、妖术在满MP时威力+33%。角色已通过种族获得白魔法的使用权限，但初始状态没有学会任何白魔法技能，因此当前没有可用的白魔法；角色本身不能使用时魔法、圣技、魔法剑、阴阳术和念动，因此这五类技能的强化当前无法发挥。黑魔法、召唤术、暗技和妖术的强化可以发挥。'
        elsif actor_id == 612 && tag == 'MP満タン威力アップスキルタイプ'
          item[:comment] = '该效果属于角色612的满MP威力强化。原始备注还包含白魔法、时魔法、圣技、魔法剑、阴阳术和念动。角色已通过种族获得白魔法的使用权限，但初始状态没有学会任何白魔法技能，因此当前没有可用的白魔法；角色本身不能使用时魔法、圣技、魔法剑、阴阳术和念动，因此这五类技能的强化当前无法发挥。黑魔法、召唤术、暗技和妖术的强化可以发挥。'
        end
        return [item]
      when '連鎖ステート'
        pairs = body.scan(/(\d+)-(\d+)/)
        return [] if pairs.empty?
        return pairs.map do |first, second|
          trigger_jp = lookup(lookups[:states], first, 'ステート')
          chained_jp = lookup(lookups[:states], second, 'ステート')
          trigger_zh = state_name_zh(lookups, first)
          chained_zh = state_name_zh(lookups, second)
          jp = "自身に「#{trigger_jp}」（ステートID #{first}）が新たに付与された時、「#{chained_jp}」（ステートID #{second}）を自動付与"
          zh = "自身新获得「#{trigger_zh}」（状态ID #{first}）时，自动附加「#{chained_zh}」（状态ID #{second}）"
          record(tag, jp, zh, 'id_pair', "#{first}-#{second}", '', 'note', "<#{content}>")
        end
      when '全攻撃属性付加'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        names = ids.map { |id| element_lookup(lookups[:elements], id) }
        return [record(tag, "全攻击附加属性：#{names.join('、')}", "所有攻击附加属性：#{names.join('、')}", 'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when 'スキルタイプ攻撃回数アップ', 'スキル攻撃回数アップ'
        pairs = body.scan(/(\d+)-(\d+)/)
        return [] if pairs.empty?
        return pairs.map do |id, count|
          name = tag.start_with?('スキルタイプ') ? skill_type_lookup(lookups[:skill_types], id) : skill_lookup(lookups[:skills], id)
          record(tag, "#{name}攻击次数 +#{count}", "#{name}攻击次数 +#{count}", 'count', count, "+#{count}", 'note', "<#{content}>")
        end
      when '回数制限自動復活'
        pair = body.match(/([+-]?\d+)\s*-\s*([+-]?\d+)/)
        return [] unless pair
        return [record(tag, "限制#{pair[1]}次的自动复活，成功率#{pair[2]}%", "限制#{pair[1]}次的自动复活，成功率#{pair[2]}%", 'count_rate', "#{pair[1]}-#{pair[2]}", "#{pair[2]}%", 'note', "<#{content}>")]
      when '獲得経験値倍率', '獲得職業経験値倍率', '獲得金額倍率', '獲得アイテム倍率', '最大TP増加', '最大TP減少', 'パーティ全員能力アップ', 'パーティ全員HPMPアップ'
        value = body[/[+-]?\d+/]
        return [] unless value
        zh = { '獲得経験値倍率' => '获得经验倍率', '獲得職業経験値倍率' => '获得职业经验倍率', '獲得金額倍率' => '获得金钱倍率', '獲得アイテム倍率' => '获得物品倍率', '最大TP増加' => '最大TP增加', '最大TP減少' => '最大TP减少', 'パーティ全員能力アップ' => '全队能力提升', 'パーティ全員HPMPアップ' => '全队HP/MP提升' }[tag]
        if ['獲得経験値倍率', '獲得職業経験値倍率', '獲得金額倍率', '獲得アイテム倍率'].include?(tag)
          display = multiplier_display(value)
          jp_label = {
            '獲得経験値倍率' => '獲得経験値倍率',
            '獲得職業経験値倍率' => '獲得職業経験値倍率',
            '獲得金額倍率' => '獲得金額倍率',
            '獲得アイテム倍率' => '獲得アイテム倍率'
          }[tag]
          zh_label = {
            '獲得経験値倍率' => '获得经验倍率',
            '獲得職業経験値倍率' => '获得职业经验倍率',
            '獲得金額倍率' => '获得金钱倍率',
            '獲得アイテム倍率' => '获得物品倍率'
          }[tag]
          jp = "#{jp_label}#{percent_ratio_phrase_jp(value)}"
          zh = "#{zh_label}#{percent_ratio_phrase_zh(value)}"
          return [record(tag, jp, zh, 'multiplier', value, display, 'note', "<#{content}>")]
        elsif tag.start_with?('最大TP')
          percentage = body.match?(/%\s*\z/)
          delta = value.to_i * (tag == '最大TP増加' ? 1 : -1)
          display = format('%+d%s', delta, percentage ? '%' : '')
          value_type = percentage ? 'additive_percent' : 'additive'
        else
          display = "+#{value}%"
          value_type = 'additive_percent'
        end
        return [record(tag, "#{tag} #{display}", "#{zh} #{display}", value_type, value, display, 'note', "<#{content}>")]
      when 'トリガーステート'
        match = body.match(/\A([HMT])\s*,\s*(\d+)\s*,\s*([+-]?\d+(?:\.\d+)?)%\s*,\s*(\d+)\z/i)
        return [] unless match
        point = match[1].upcase
        trigger = match[2].to_i
        threshold = match[3]
        state_id = match[4]
        point_jp = { 'H' => 'HP', 'M' => 'MP', 'T' => 'TP' }[point] || point
        point_zh = point_jp
        state = lookup(lookups[:states], state_id, '状态')
        state_zh = normalize_state_name_zh(translate_name(state))
        condition = case trigger
                    when 0 then ["#{point_jp}が#{threshold}%未満になると", "#{point_zh}低于#{threshold}%时"]
                    when 1 then ["#{point_jp}が#{threshold}%以上になると", "#{point_zh}达到#{threshold}%以上时"]
                    when 2 then ["#{point_jp}が#{threshold}%未満になると", "#{point_zh}低于#{threshold}%时"]
                    when 3 then ["#{point_jp}が#{threshold}%以上になると", "#{point_zh}达到#{threshold}%以上时"]
                    else ["#{point_jp}条件（触发值#{trigger}、阈値#{threshold}%）", "#{point_zh}条件（触发值#{trigger}、阈值#{threshold}%）"]
                    end
        action_jp = trigger / 2 == 0 ? '状態を付与' : '状態を解除'
        jp = "#{condition[0]}#{state}（#{action_jp}）"
        direct_effect = TRIGGER_STATE_DIRECT_EFFECTS[state_id.to_i]
        zh = if direct_effect
             if trigger / 2 == 0
                 "#{condition[1]}获得「#{direct_effect}」效果"
               else
                 "#{condition[1]}解除「#{direct_effect}」效果"
               end
             elsif trigger / 2 == 0
               "#{condition[1]}获得「#{state_zh}」效果"
             else
               "#{condition[1]}解除「#{state_zh}」效果"
             end
        item = record(tag, jp, zh, 'threshold_state', "#{point},#{trigger},#{threshold},#{state_id}", "#{point_zh} #{threshold}%", 'note', "<#{content}>")
        if point == 'H' && trigger == 0 && threshold.to_f == 20.0 && state_id.to_i == 221
          if actor_id == 68
            item[:comment] = '状态221「解除限制器」会使角色进入自动战斗状态，无法由玩家手动选择行动；同时使攻击力、防御力、魔力、精神力、敏捷和灵巧变为原来的150%，并使技能类型ID 6至21及50至62的技能连续发动2次。因此该状态同时实现了“濒死时失去控制”“六项战斗能力大幅提升”和“部分技能连续发动两次”；这里并不是额外增加一次行动。'
          elsif actor_id == 69
            item[:comment] = '固有能力只写明濒死时全能力大幅提升，但状态221「解除限制器」的实际效果还包括进入自动战斗状态，以及使技能类型ID 6至21及50至62的技能连续发动2次。能力值方面，实际是攻击力、防御力、魔力、精神力、敏捷和灵巧变为原来的150%，不包括最大HP和最大MP。'
          end
        end
        return [item]
      when '無効化反撃スキル', '無効化魔法反撃スキル', '無効化必中反撃スキル'
        pair = body.match(/(\d+)\s*,\s*([+-]?\d+)/)
        return [] unless pair
        skill = skill_lookup(lookups[:skills], pair[1])
        skill_jp = skill.sub(/\A反撃：/, '')
        skill_zh = translate_name(skill).sub(/\A反击：/, '')
        attack_type = {
          '無効化反撃スキル' => ['物理攻撃', '物理攻击'],
          '無効化魔法反撃スキル' => ['魔法攻撃', '魔法攻击'],
          '無効化必中反撃スキル' => ['必中攻撃', '必中攻击']
        }[tag]
        percent = pair[2]
        jp = "#{attack_type[0]}を受けた時、#{percent}%の確率でダメージを無効化し、「#{skill_jp}」で反撃"
        zh = "受到#{attack_type[1]}时，以#{percent}%概率完全无效化伤害，并以「#{skill_zh}」反击"
        return [record(tag, jp, zh, 'chance', percent, "#{percent}%", 'note', "<#{content}>")]
      when '必中反撃スキル', '魔法反撃スキル', '反撃スキル', '回避時スキル'
        pair = body.match(/(\d+)\s*,\s*([+-]?\d+)/)
        return [] unless pair
        skill = skill_lookup(lookups[:skills], pair[1])
        skill_jp = skill.sub(/\A(?:発動|反撃)：/, '')
        skill_zh = translate_name(skill).sub(/\A(?:发动|反击)：/, '')
        label_jp = { '必中反撃スキル' => '必中反撃スキル', '魔法反撃スキル' => '魔法反撃スキル', '反撃スキル' => '反撃スキル', '回避時スキル' => '回避時発動スキル' }[tag]
        label_zh = { '必中反撃スキル' => '必中反击技能', '魔法反撃スキル' => '魔法反击技能', '反撃スキル' => '反击技能', '回避時スキル' => '闪避时发动技能' }[tag]
        return [record(tag, "#{label_jp}「#{skill_jp}」：#{pair[2]}%", "#{label_zh}「#{skill_zh}」：#{pair[2]}%", 'chance', pair[2], "#{pair[2]}%", 'note', "<#{content}>")]
      when 'スキル無効化反撃', 'スキルタイプ無効化反撃'
        match = body.match(/\A(\d+)\s*,\s*((?:\d+\s*,?\s*)+)\z/)
        return [] unless match
        counter_skill_id = match[1]
        target_ids = match[2].scan(/\d+/)
        counter_skill = skill_lookup(lookups[:skills], counter_skill_id)
        type_entry = tag == 'スキルタイプ無効化反撃'
        target_collection = type_entry ? lookups[:skill_types] : lookups[:skills]
        target_fallback = type_entry ? '技能类型' : '技能'
        target_names = target_ids.map do |id|
          type_entry ? skill_type_lookup(target_collection, id) : skill_lookup(target_collection, id)
        end
        counter_skill_jp = counter_skill.sub(/\A(?:発動|反撃)：/, '')
        counter_skill_zh = translate_name(counter_skill).sub(/\A(?:发动|反击)：/, '')
        target_names_zh = target_names.map { |name| translate_name(name) }
        jp = "#{target_names.join('、')}を無効化し、「#{counter_skill_jp}」で反撃"
        zh = "无效化#{target_names_zh.join('、')}，并以「#{counter_skill_zh}」反击"
        value_raw = "#{counter_skill_id},#{target_ids.join(',')}"
        item = record(tag, jp, zh, 'id_mapping', value_raw, '', 'note', "<#{content}>")
        item[:comment] = if type_entry
                           "反击技能：#{id_name_entry(counter_skill_id, lookups[:skills], '技能')}；被无效化技能类型：#{id_name_entries(target_ids, lookups[:skill_types], '技能类型')}"
                         else
                           "反击技能：#{id_name_entry(counter_skill_id, lookups[:skills], '技能')}；被无效化技能：#{id_name_entries(target_ids, lookups[:skills], '技能')}"
                         end
        return [item]
      when 'MP再生率固定', 'TP再生率固定'
        value = body[/[+-]?\d+(?:\.\d+)?/]
        return [] unless value
        label = tag == 'MP再生率固定' ? 'MP再生率' : 'TP再生率'
        zh_label = tag == 'MP再生率固定' ? 'MP再生率' : 'TP再生率'
        display = "#{value}%"
        return [record(tag, "#{label}を#{display}に固定", "#{zh_label}固定为#{display}", 'fixed_percent', value, display, 'note', "<#{content}>")]
      when 'MPタイプ消費なし', 'TPタイプ消費なし', 'HPタイプ消費なし', 'MPスキル消費なし', 'TPスキル消費なし', 'HPスキル消費なし'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        type_entry = tag.include?('タイプ')
        cost_type = tag[0, 2]
        names = ids.map { |id| type_entry ? skill_type_lookup(lookups[:skill_types], id) : skill_lookup(lookups[:skills], id) }
        return [record(tag, "#{names.join('、')}不消耗#{cost_type}", "#{names.join('、')}不消耗#{cost_type}", 'id_list', ids.join(','), '0%', 'note', "<#{content}>")]
      when '消費アイテム節約スキルタイプ', '消費アイテム節約'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |id, amount|
          if tag.include?('スキルタイプ')
            name = skill_type_lookup(lookups[:skill_types], id)
            record(tag, "#{name}使用時、消費アイテムを#{amount}%の確率で節約", "使用#{translate_name(name)}时，#{amount}%概率不消耗道具",
                   'chance', amount, "#{amount}%", 'note', "<#{content}>")
          else
            name = item_lookup(lookups[:items], id)
            name_zh = translate_name(name)
            record(tag, "#{name}を使用時、#{amount}%の確率で消費しない", "使用#{name_zh}时，#{amount}%概率不消耗该道具",
                   'chance', amount, "#{amount}%", 'note', "<#{content}>")
          end
        end
      when 'スキルタイプ属性追加'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |stype_id, element_id|
          stype = skill_type_lookup(lookups[:skill_types], stype_id)
          element = element_lookup(lookups[:elements], element_id)
          suspected = SUSPECTED_ATTRIBUTE_ID_NOTES[[actor_id, element_id.to_i]]
          if suspected
            jp_element = "属性ID #{element_id}（対応不明の属性）"
            zh_element = "ID #{element_id}属性（无对应属性）"
            item = record(tag, "#{stype}に#{jp_element}を追加", "#{translate_name(stype)}附加#{zh_element}", 'id_pair', "#{stype_id}-#{element_id}", '', 'note', "<#{content}>")
            item[:comment] = suspected
            item
          else
            stype_zh = translate_name(stype)
            element_zh = translate_name(element)
            record(tag, "#{stype}に#{element}属性を追加", "#{stype_zh}附加#{element_zh}属性", 'id_pair', "#{stype_id}-#{element_id}", '', 'note', "<#{content}>")
          end
        end
      when 'ヒット数で威力アップ'
        value = body[/[+-]?\d+(?:\.\d+)?/]
        return [] unless value
        item = record(tag,
                      "連撃の各段階のダメージが前の一撃の#{value}%になる",
                      "连击每段伤害变为前一击的#{value}%",
                      'multiplier', value, "×#{value}%", 'note', "<#{content}>")
        item[:comment] = "每增加1次命中，后续该段伤害倍率乘以#{value}%（第n段为#{value}%^(n−1)），各段伤害分别结算后相加。"
        return [item]
      when '踏みとどまり'
        value = body[/[+-]?\d+(?:\.\d+)?/]
        return [] unless value
        item = record(tag,
                      "現在HPが最大HPの#{value}%を超えている時、致死ダメージを受けてもHP1で生存（戦闘ごとに1回）",
                      "当前HP高于最大HP的#{value}%时，受到致死伤害会以1 HP存活（每场战斗一次）",
                      'hp_threshold', value, ">#{value}%", 'note', "<#{content}>")
        item[:comment] = "#{value}%是当前HP门槛而非发动概率；当前HP必须严格高于该比例。若同时存在多个该能力，游戏取最低门槛，发动次数仍为每场战斗一次。"
        return [item]
      when 'スティール成功率', 'チェーン強化', '反撃強化', 'ヒット数で威力ダウン', 'ステート特攻強化', '反射ダメージ増加', 'ターン内ダメージ減少'
        value = body[/[+-]?\d+/]
        return [] unless value
        zh = { 'スティール成功率' => '偷窃成功率', 'チェーン強化' => '技能链威力强化', '反撃強化' => '反击强化', 'ヒット数で威力アップ' => '随连击数提升威力', 'ヒット数で威力ダウン' => '随连击数降低威力', 'ステート特攻強化' => '异常状态特攻强化', '反射ダメージ増加' => '反射伤害增加', '必中ダメージ率' => '必中伤害倍率', 'ターン内ダメージ減少' => '回合内伤害衰减' }[tag]
        return [record(tag, "#{tag} #{value}%", "#{zh} #{value}%", 'additive_percent', value, "+#{value}%", 'note', "<#{content}>")]
      when 'ダメージゴールド回収'
        value = body[/[+-]?\d+/]
        return [] unless value
        return [record(tag, "被ダメージ時、ダメージの#{value}%をお金として回収", "受到伤害时，获得相当于伤害量#{value}%的金币", 'additive_percent', value, "+#{value}%", 'note', "<#{content}>")]
      when 'ダメージMP吸収'
        value = body[/[+-]?\d+/]
        return [] unless value
        return [record(tag, "被ダメージ時、ダメージの#{value}%をMPとして回復", "受到伤害时，恢复相当于伤害量#{value}%的MP", 'additive_percent', value, "+#{value}%", 'note', "<#{content}>")]
      when '必中ダメージ率'
        value = body[/[+-]?\d+(?:\.\d+)?/]
        return [] unless value
        return [record(tag, "必中ダメージ量#{percent_ratio_phrase_jp(value)}", "必中攻击伤害#{percent_ratio_phrase_zh(value)}", 'multiplier', value, multiplier_display(value), 'note', "<#{content}>")]
      when '特殊カテゴリー与ダメージアップ強化'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        category_ids = pairs.map { |category_id, _amount| category_id.to_i }
        amounts = pairs.map { |_category_id, amount| amount.to_i }
        if category_ids == STANDARD_EX_CATEGORY_IDS && amounts.uniq.length == 1
          amount = amounts.first
          excluded_jp = (39..42).map { |id| ex_category_names(id)[0] }.join('・')
          excluded_zh = ['ID 36预留种族'] + (39..42).map { |id| ex_category_names(id)[1] }
          jp = "全通常種族への特攻強化 +#{amount}%（#{excluded_jp}を除く）"
          zh = "对所有通常种族的特攻强化 +#{amount}%（不含#{excluded_zh.join('、')}）"
          item = record(tag, jp, zh, 'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
          item[:comment] = '原始标签列出了特殊类别ID 10至35中的全部已定义类别，以及ID 37、38；ID 36在原版和汉化版游戏脚本中均未定义类别名称，属于编号空缺。标签未包含39（梦魔）、40（飞行）、41（神）和42（魔王），因此强化不适用于这四类目标。'
          return [item]
        end
        return pairs.map do |category_id, amount|
          category_jp, category_zh = ex_category_names(category_id)
          jp = "#{category_jp}への特攻強化 #{signed_number(amount.to_f)}%"
          zh = "对#{category_zh}特攻强化 #{signed_number(amount.to_f)}%"
          record(tag, jp, zh, 'additive_percent', amount, "#{signed_number(amount.to_f)}%", 'note', "<#{content}>")
        end
      when '特殊カテゴリー与ダメージアップ', '特殊カテゴリー被ダメージダウン'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |category_id, amount|
          category_jp, category_zh = ex_category_names(category_id)
          if tag == '特殊カテゴリー被ダメージダウン'
            jp = "#{category_jp}から受けるダメージを#{amount}%軽減"
            zh = "受到#{category_zh}的伤害降低 #{amount}%"
          else
            jp = "#{category_jp}への特攻 +#{amount}%"
            zh = "对#{category_zh}特攻 +#{amount}%"
          end
          record(tag, jp, zh, 'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
        end
      when '特殊カテゴリー与ダメージアップスキルタイプ'
        triples = body.scan(/(\d+)-(\d+)-([+-]?\d+)/)
        return [] if triples.empty?
        return triples.map do |stype_id, category_id, amount|
          stype = skill_type_lookup(lookups[:skill_types], stype_id)
          stype_zh = translate_name(stype)
          category_jp, category_zh = ex_category_names(category_id)
          record(tag, "#{stype}で#{category_jp}に特攻 +#{amount}%", "使用#{stype_zh}时，对#{category_zh}特攻 +#{amount}%", 'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
        end
      when '戦闘開始時発動', 'ターン開始時発動', 'ターン終了時発動'
        match = body.match(/\A(?:(\d+)\s*:\s*)?(\d+)\s*,\s*([+-]?\d+)%?(?:\s*,\s*(\d+)\s*,\s*((?:\d+\s*,?\s*)+))?\z/)
        return [] unless match
        skill = skill_lookup(lookups[:skills], match[2])
        skill_zh = translate_name(skill)
        skill_zh = skill_zh.sub(/\A发动：/, '')
        timing_jp = { '戦闘開始時発動' => '戦闘開始時', 'ターン開始時発動' => 'ターン開始時', 'ターン終了時発動' => 'ターン終了時' }[tag]
        timing_zh = { '戦闘開始時発動' => '战斗开始时', 'ターン開始時発動' => '回合开始时', 'ターン終了時発動' => '回合结束时' }[tag]
        priority_jp = match[1] ? "（優先度#{match[1]}）" : ''
        priority_zh = match[1] ? "（优先级#{match[1]}）" : ''
        condition_type = match[4].to_i if match[4]
        condition_ids = match[5].to_s.scan(/\d+/).map(&:to_i)
        condition = auto_skill_condition_text(condition_type, condition_ids, lookups)
        jp_action = "#{timing_jp}#{match[3]}%で#{skill}を発動#{priority_jp}"
        zh_action = if tag == 'ターン終了時発動'
                      "#{timing_zh}有#{match[3]}%概率发动#{skill_zh}#{priority_zh}"
                    else
                      "#{timing_zh}#{match[3]}%发动#{skill_zh}#{priority_zh}"
                    end
        jp = condition ? "#{condition[0]}、#{jp_action}" : jp_action
        zh = condition ? "#{condition[1]}，#{zh_action}" : zh_action
        return [record(tag, jp, zh, 'chance', match[3], "#{match[3]}%", 'note', "<#{content}>")]
      when 'スキルタイプスティール付与'
        pairs = body.scan(/(\d+)-(\d+)/)
        return [] if pairs.empty?
        return pairs.map do |stype_id, steal_id|
          stype = skill_type_lookup(lookups[:skill_types], stype_id)
          stype_zh = translate_name(stype)
          steal_names = {
            '1' => ['アイテム', '物品'],
            '2' => ['食べ物', '食物'],
            '3' => ['素材', '素材'],
            '4' => ['下着', '内裤']
          }
          steal_name = steal_names[steal_id]
          if steal_name
            item = record(tag, "#{stype}に#{steal_name[0]}スティール効果を付加", "#{stype_zh}附加#{steal_name[1]}偷窃效果", 'id_pair', "#{stype_id}-#{steal_id}", '', 'note', "<#{content}>")
            item[:comment] = "偷窃列表ID #{steal_id}对应#{steal_name[1]}偷窃；游戏中的ID 1、2、3、4分别对应物品、食物、素材和内裤。"
            item
          else
            record(tag, "#{stype}にスティール効果（リストID #{steal_id}）を付加", "#{stype_zh}附加偷窃效果（列表ID #{steal_id}）", 'id_pair', "#{stype_id}-#{steal_id}", '', 'note', "<#{content}>")
          end
        end
      when '二刀流強化', '三刀流強化'
        values = body.scan(/[+-]?\d+/)
        return [] if values.empty?
        wield_jp = tag == '二刀流強化' ? '二刀流' : '三刀流'
        wield_zh = tag == '二刀流強化' ? '二刀流' : '三刀流'
        amount = values.first.to_i
        amount_text = amount >= 0 ? "+#{amount}%" : "#{amount}%"
        jp = "#{wield_jp}時、装備武器の能力値 #{amount_text}"
        zh = if amount >= 0
               "#{wield_zh}时，所装备武器的能力值提升#{amount}%"
             else
               "#{wield_zh}时，所装备武器的能力值降低#{amount.abs}%"
             end
        comment = if values.length > 1
                    "源码参数为 #{values.join(',')}；当前游戏脚本实际使用第一个参数，后续参数未单独读取。"
                  else
                    '当前游戏脚本实际使用该参数。'
        end
        item = record(tag, jp, zh, 'additive_percent', values.first, amount_text, 'note', "<#{content}>")
        item[:comment] = comment
        return [item]
      when 'スキルタイプコンボ'
        pairs = body.scan(/(\d+)-(\d+)/)
        return [] if pairs.empty?
        return pairs.map do |stype_id, skill_id|
          stype = skill_type_lookup(lookups[:skill_types], stype_id)
          skill_jp = skill_lookup(lookups[:skills], skill_id).sub(/\A発動：/, '')
          skill_zh = translate_name(skill_lookup(lookups[:skills], skill_id)).sub(/\A发动：/, '')
          record(tag, "#{stype}から連携発動：#{skill_jp}", "#{translate_name(stype)}可以连携发动：#{skill_zh}", 'id_pair', "#{stype_id}-#{skill_id}", '', 'note', "<#{content}>")
        end
      when '回避時スキル無効', '死亡時スキル無効'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        names_jp = ids.map { |id| skill_lookup(lookups[:skills], id).sub(/\A発動：/, '') }
        names_zh = ids.map { |id| translate_name(skill_lookup(lookups[:skills], id)).sub(/\A发动：/, '') }
        targets_jp = names_jp.map { |name| "「#{name}」" }.join('、')
        targets_zh = names_zh.map { |name| "「#{name}」" }.join('、')
        if tag == '死亡時スキル無効'
          return [record(tag, "戦闘不能時、#{targets_jp}は発動しない", "战斗不能时不会发动#{targets_zh}",
                         'id_list', ids.join(','), '', 'note', "<#{content}>")]
        end
        return [record(tag, "回避時、#{targets_jp}は発動しない", "闪避时不会发动#{targets_zh}",
                       'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when '砂漠地形強化', '市街地形強化', '洞窟地形強化'
        return [record(tag, tag, tag.sub('強化', '强化'), 'boolean', '', '', 'note', "<#{content}>")]
      when '仲間加入倍率'
        value = body[/[+-]?\d+/]
        return [] unless value
        return [record(tag, "仲間加入成功率#{percent_ratio_phrase_jp(value)}", "伙伴加入成功率#{percent_ratio_phrase_zh(value)}", 'multiplier', value, multiplier_display(value), 'note', "<#{content}>")]
      when 'スキルタイプHP還元'
        pair = body.match(/(\d+)\s*,\s*([+-]?\d+)/)
        return [] unless pair
        stype = skill_type_lookup(lookups[:skill_types], pair[1])
        return [record(tag, "#{stype}伤害的#{pair[2]}%转化为HP", "#{stype}伤害的#{pair[2]}%转化为HP", 'additive_percent', pair[2], "#{pair[2]}%", 'note', "<#{content}>")]
      when '死亡時スキル', '最終反撃'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        names = ids.map { |id| skill_lookup(lookups[:skills], id) }
        quoted_names = names.map { |name| "「#{name}」" }.join('、')
        return [record(tag, "战斗不能时发动#{quoted_names}", "战斗不能时发动#{quoted_names}", 'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when '無効化障壁'
        value = body[/[+-]?\d+/]
        return [] unless value
        return [record(tag, "无效化护盾：#{value}", "无效化护盾：#{value}", 'dynamic', value, '', 'note', "<#{content}>")]
      when '自己ステート延長', '相手ステート延長'
        pairs = body.scan(/(\d+)-(\d+)/)
        return [] if pairs.empty?
        target_jp = tag.start_with?('自己') ? '自身' : '相手'
        target_zh = tag.start_with?('自己') ? '自身' : '对方'
        return pairs.map do |state_id, turns|
          state = lookup(lookups[:states], state_id, '状态')
          state_zh = normalize_state_name_zh(translate_name(state))
          record(tag, "#{target_jp}の「#{state}」を#{turns}ターン延長", "#{target_zh}的「#{state_zh}」状态延长#{turns}回合", 'count', turns, "+#{turns}回合", 'note', "<#{content}>")
        end
      when '自己ステート永続', '相手ステート永続'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        target = tag.start_with?('自己') ? '自身' : '对方'
        names = ids.map { |id| lookup(lookups[:states], id, '状态') }
        return [record(tag, "#{target}状态永久化：#{names.join('、')}", "#{target}状态永久化：#{names.join('、')}", 'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when '両手盾時能力'
        id = body[/\d+/]
        return [] unless id
        return [record(tag, "双手盾时追加能力ID #{id}", "双手盾时追加能力ID #{id}", 'id', id, '', 'note', "<#{content}>")]
      when '武器マスタリー', '防具マスタリー'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |type_id, amount|
          collection = tag.start_with?('武器') ? lookups[:weapon_types] : lookups[:armor_types]
          name = lookup(collection, type_id, '装备类型')
          record(tag, "#{name}精通 #{amount}%", "#{name}精通 #{amount}%", 'additive_percent', amount, "+#{amount}%", 'note', "<#{content}>")
        end
      when '必要アイテム無視', '武器ボーナス取得'
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        if tag == '必要アイテム無視'
          item_details = ids.map do |id|
            name = item_lookup(lookups[:items], id)
            translated_name = translate_name(name)
            "#{id}（#{translated_name}）"
          end
          item = record(tag,
                        '体内に組み込まれた一部の「マキナ」を使用する際、対応するアイテムの所持は不要',
                        '使用体内组装的部分「器械」时无需持有对应道具',
                        'id_list', ids.join(','), '', 'note', "<#{content}>")
          item[:comment] = "无视所需物品ID：#{item_details.join('、')}"
          return [item]
        end
        weapon_names_jp = ids.map { |id| lookup(lookups[:weapon_types], id, '武器类型') }
        weapon_names_zh = weapon_names_jp.map { |name| translate_name(name) }
        jp = "#{weapon_names_jp.join('・')}を武器関連倍率の判定対象に追加（装備可能化ではない）"
        zh = "使用技能时，视为装备了#{weapon_names_zh.join('、')}"
        item = record(tag, jp, zh, 'weapon_type_list', ids.join(','), '', 'note', "<#{content}>")
        item[:comment] = "对应武器类型：#{id_name_entries(ids, lookups[:weapon_types], '武器类型')}；该能力只影响武器相关倍率和武器类型加成的判定，不增加装备资格。"
        return [item]
      when '属性耐性固定'
        pairs = body.scan(/(\d+)-([+-]?\d+)/)
        return [] if pairs.empty?
        return pairs.map do |element_id, amount|
          element = element_lookup(lookups[:elements], element_id)
          fixed_jp = fixed_ratio_phrase_jp(amount)
          fixed_zh = fixed_ratio_phrase_zh(amount)
          record(tag, "#{element}属性ダメージ倍率固定#{fixed_jp}", "受到#{element}属性伤害倍率固定为#{fixed_zh}", 'multiplier', amount, multiplier_display(amount), 'note', "<#{content}>")
        end
      when 'HP消費率', 'MP消費率', 'TP消費率', 'ゴールド消費率', '物理ダメージ率', '魔法ダメージ率'
        value = body[/[+-]?\d+(?:\.\d+)?/]
        return [] unless value
        if tag.end_with?('ダメージ率')
          target_jp = tag.start_with?('物理') ? '受ける物理ダメージ' : '受ける魔法ダメージ'
          target_zh = tag.start_with?('物理') ? '受到的物理伤害' : '受到的魔法伤害'
        else
          target_jp = tag.sub('率', '量')
          target_zh = { 'HP消費率' => 'HP消耗量', 'MP消費率' => 'MP消耗量', 'TP消費率' => 'SP消耗量', 'ゴールド消費率' => '金币消耗量' }[tag]
        end
        return [record(tag, "#{target_jp}#{percent_ratio_phrase_jp(value)}", "#{target_zh}#{percent_ratio_phrase_zh(value)}", 'multiplier', value, multiplier_display(value), 'note', "<#{content}>")]
      when '戦闘不能にならない', '毎ターン復活'
        zh = tag == '戦闘不能にならない' ? '不会进入战斗不能状态' : '每回合复活'
        return [record(tag, tag, zh, 'boolean', '', '', 'note', "<#{content}>")]
      when '通常攻撃強化'
        pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
        return [] if pairs.empty?

        return pairs.group_by { |_weapon_type_id, amount| amount }.map do |amount, entries|
          weapon_type_ids = entries.map(&:first)
          names_jp = weapon_type_ids.map { |id| lookup(lookups[:weapon_types], id, '武器类型') }
          names_zh = names_jp.map { |name| translate_name(name) }
          jp = "#{names_jp.join('・')}装備時、通常攻撃の威力 +#{amount}%"
          zh = "装备#{names_zh.join('或')}时，普通攻击威力 +#{amount}%"
          mapping_raw = entries.map { |weapon_type_id, value| "#{weapon_type_id}-#{value}" }.join(',')
          item = record(tag, jp, zh, 'weapon_type_mapping', mapping_raw, "+#{amount}%", 'note', "<#{content}>")
          item[:zh] = zh
          item[:comment] = "武器类型：#{id_name_entries(weapon_type_ids, lookups[:weapon_types], '武器类型')}"
          item
        end
      when '最速ダメージアップ'
        value = body[/[+-]?\d+/]
        return [] unless value
        return [record(tag, "#{tag} +#{value}%", "最速行动伤害提升 +#{value}%", 'additive_percent', value, "+#{value}%", 'note', "<#{content}>")]
      when '職業アップ', '行動変化'
        pairs = body.scan(/(\d+)-(\d+)/)
        return [] if pairs.empty?
        return pairs.map do |first, second|
          if tag == '職業アップ'
            name = lookup(lookups[:classes], first, '职业')
            record(tag, "#{name}强化 +#{second}%", "#{name}强化 +#{second}%", 'additive_percent', second, "+#{second}%", 'note', "<#{content}>")
          else
            skill = skill_lookup(lookups[:skills], first)
            skill_zh = translate_name(skill)
            jp = "#{second}%の確率で、そのターンの行動を「#{skill}」に変更"
            zh = "#{second}%概率将本回合行动改为发动「#{skill_zh}」"
            item = record(tag, jp, zh, 'chance', "#{first}-#{second}", "#{second}%", 'note', "<#{content}>")
            if actor_id == 566 && first == '28' && second == '20'
              item[:comment] = '原始标签<行動変化 28-20>会以20%概率将当回合行动替换为技能ID 28「遊ぶ」（玩）。该技能调用的公共事件包含角色566专属的8种随机结果：其中4种会发动技能ID 3313「遊ぶ：若さゆえの過ち」，该技能以自身为目标，按自身最大HP的10%计算物理伤害，并有±20%的伤害波动；另外4种会进入“变得懒散”的分支。因此固有能力说明中的“战斗中有几率被殴打”并非虚标，而是对其中一半随机分支的概括。'
            end
            item
          end
        end
      when 'TPLv補正', 'TPLv100補正'
        value = body[/[+-]?\d+(?:\.\d+)?/]
        return [] unless value
        zh = tag == 'TPLv補正' ? 'TP等级修正' : 'TP等级100修正'
        return [record(tag, "#{tag} #{value}", "#{zh} #{value}", 'raw_number', value, value, 'note', "<#{content}>")]
      when 'スキルチェーン'
        ids = body.scan(/\d+/).map(&:to_i)
        return [] if ids.empty?
        names_jp = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
        # Use the complete translation table as a fallback; the legacy short table
        # does not contain every skill type and otherwise produced empty arrows.
        names_zh = names_jp.map { |name| translate_name(name) }
        item = record(tag, "#{names_jp.join('→')}スキルチェーン", "#{names_zh.join('→')}技能链", 'id_list', ids.join(','), '', 'note', "<#{content}>")
        if actor_id == 489 && ids == [26, 21, 26]
          item[:comment] = '固有能力描述写成「投掷技或白魔法→格斗→圣技」，但原始备注实际指定的是「圣技→格斗→圣技」；技能类型ID 16 才是投掷技，ID 26 是圣技，因此很可能是作者将16误写成了26。当前这条备注不能由投掷技起手；另一条「白魔法→格斗→圣技」技能链仍可正常发动。'
        elsif actor_id == 493 && ids == [26, 15, 25]
          item[:comment] = '原始备注指定技能链为「圣技→鞭技→召唤术」，但同一组固有能力中的其他相关标签均作用于弓技，因此很可能是作者误将技能类型ID 14（弓技）写成了15（鞭技）。角色已通过职业获得鞭技使用权限，但初始状态没有学会任何鞭技技能，因此当前无法完整发动该技能链。'
        end
        [item]
      when 'HPタイプ消費率', 'MPタイプ消費率', 'TPタイプ消費率', 'HPスキル消費率', 'MPスキル消費率', 'TPスキル消費率'
        pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
        if pairs.empty?
          pair = body.match(/\A(\d+)\s*,\s*([+-]?\d+)/)
          pairs = [[pair[1], pair[2]]] if pair
        end
        return [] if pairs.empty?
        return pairs.map do |id_text, value_text|
          type_entry = tag.include?('タイプ')
          cost_type = tag[0, 2]
          jp_name = type_entry ? skill_type_lookup(lookups[:skill_types], id_text) : skill_lookup(lookups[:skills], id_text)
          cn_name = translate_name(jp_name)
          display = multiplier_display(value_text)
          item = record(tag, "#{jp_name}#{cost_type}消費量#{percent_ratio_phrase_jp(value_text)}", "#{cn_name.empty? ? jp_name : cn_name}#{cost_type}消耗量#{percent_ratio_phrase_zh(value_text)}", 'multiplier', value_text, display, 'note', "<#{content}>")
          if actor_id == 502 && tag == 'TPタイプ消費率' && id_text == '43' && value_text.to_f == 300.0
            item[:comment] = '固有能力说明写成「器械」SP消耗量变为2倍（200%），但原始备注<TPタイプ消費率 43,300%>实际使技能类型ID 43「器械」的SP消耗量变为300%（增加200%），即3倍；两者不一致。'
          elsif actor_id == 571 && tag == 'TPタイプ消費率' && id_text == '18' && value_text.to_f == 66.0
            item[:comment] = '固有能力说明写成「海贼技」「跳舞」的SP消耗量变为约2/3，但原始备注实际分别指定海贼技（ID 32）和扇技（ID 18）的SP消耗量变为66%（减少34%），没有配置舞蹈（ID 37）的减耗效果。作者很可能将舞蹈的技能类型ID 37误写成了扇技的ID 18。角色本身不能使用扇技，因此扇技减耗部分通常无法发挥作用；海贼技减耗部分可以正常生效。'
          elsif actor_id == 442 && tag == 'MPタイプ消費率' && id_text == '22' && value_text.to_f == 66.0
            item[:comment] = '固有能力说明写成「白魔法」MP消耗减半（50%），但原始备注<MPタイプ消費率 22-66>实际使技能类型ID 22「白魔法」的MP消耗量变为66%（减少34%），不是减半。'
          end
          item
        end
      when 'チェーン消費軽減'
        value = body.match(/([+-]?\d+)/)
        return [] unless value
        display = multiplier_display(value[1])
        item = record(tag, "技能チェーン消費量#{percent_ratio_phrase_jp(value[1])}", "技能链消耗量#{percent_ratio_phrase_zh(value[1])}", 'multiplier', value[1], display, 'note', "<#{content}>")
        if actor_id == 483 && value[1].to_f == 25.0
          item[:comment] = '固有能力说明写成连锁发动技能的MP及SP消耗减半（50%），但原始备注<チェーン消費軽減 25%>实际使技能链消耗量变为25%（减少75%），不是减半；该标签同时作用于技能链中的MP和SP消耗。'
        elsif actor_id == 534 && value[1].to_f == 25.0
          item[:comment] = '固有能力说明写成连锁发动技能的SP消耗减半（50%），但原始备注<チェーン消費軽減 25%>实际使技能链中的SP消耗量变为25%（减少75%），不是减半。该标签的机制也会以相同倍率作用于技能链中的MP消耗，但固有能力说明没有提及这一点。'
        elsif actor_id == 624 && value[1].to_f == 25.0
          item[:comment] = '固有能力说明写成连锁发动技能的MP及SP消耗减半（50%），但原始备注<チェーン消費軽減 25%>实际使技能链中的MP和SP消耗量均变为25%（减少75%），不是减半。'
        end
        return [item]
      when '能力値置き換え'
        parsed = parse_stat_replacement(body)
        return [] unless parsed

        stype_ids, source_id, replacement_id = parsed
        stype_jp = skill_type_names(stype_ids, lookups, false)
        stype_zh = skill_type_names(stype_ids, lookups, true)
        source_jp, source_zh = ability_value_names(source_id)
        replacement_jp, replacement_zh = ability_value_names(replacement_id)
        jp = "#{stype_jp}の#{source_jp}計算は、#{source_jp}と#{replacement_jp}の高い方を使用"
        zh = "#{stype_zh}计算#{source_zh}时，取#{source_zh}与#{replacement_zh}中的较高值"
        display = "技能类型ID #{stype_ids.join(',')}：#{source_zh}与#{replacement_zh}取较高值"
        [record(tag, jp, zh, 'stat_reference', body, display, 'note', "<#{content}>")]
      when '能力値加算'
        parsed = parse_stat_addition(body)
        return [] unless parsed

        stype_id, target_id, added_id, rate = parsed
        stype_jp = skill_type_names([stype_id], lookups, false)
        stype_zh = skill_type_names([stype_id], lookups, true)
        target_jp, target_zh = ability_value_names(target_id)
        added_jp, added_zh = ability_value_names(added_id)
        rate_text = stat_rate_text(rate)
        jp = "#{stype_jp}の#{target_jp}参照に#{rate_text}%の#{added_jp}を加算"
        zh = "#{stype_zh}计算#{target_zh}时，额外加上#{rate_text}%的#{added_zh}"
        display = "技能类型ID #{stype_id}：#{target_zh} + #{added_zh}×#{rate_text}%"
        return [record(tag, jp, zh, 'additive_stat_percent', body, display, 'note', "<#{content}>")]
      when '属性追加', '属性吸収', '属性反射', '属性貫通'
        if tag == '属性追加'
          pairs = body.scan(/(\d+)\s*,\s*(\d+)/)
          return [] if pairs.empty?
          descriptions = pairs.map do |source_id, added_id|
            source = element_lookup(lookups[:elements], source_id)
            added = element_lookup(lookups[:elements], added_id)
            source_zh = translate_name(source)
            added_zh = translate_name(added)
            ["#{source}属性攻撃に#{added}属性を追加", "#{source_zh}属性攻击时附加#{added_zh}属性"]
          end
          jp = descriptions.map(&:first).join('；')
          zh = descriptions.map(&:last).join('；')
          return [record(tag, jp, zh, 'id_pairs', pairs.map { |source_id, added_id| "#{source_id},#{added_id}" }.join(';'), '', 'note', "<#{content}>")]
        end

        ids = body.scan(/\d+/).map(&:to_i)
        return [] if ids.empty?

        descriptions = ids.map do |element_id|
          element = element_lookup(lookups[:elements], element_id)
          element_zh = translate_name(element)
          jp_text, zh_text = case tag
                             when '属性吸収'
                               ["#{element}属性ダメージを吸収（属性ID #{element_id}）",
                                "吸收#{element_zh}属性伤害（属性ID #{element_id}）"]
                             when '属性反射'
                               ["#{element}属性ダメージを反射（属性ID #{element_id}）",
                                "反射#{element_zh}属性伤害（属性ID #{element_id}）"]
                             else
                               ["#{element}属性耐性を貫通（属性ID #{element_id}）",
                                "无视#{element_zh}属性抗性（属性ID #{element_id}）"]
                             end
          [jp_text, zh_text]
        end
        jp = descriptions.map(&:first).join('；')
        zh = descriptions.map(&:last).join('；')
        return [record(tag, jp, zh, 'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when '戦闘開始時発動', 'ターン終了時発動', '反撃スキル'
        zh_label = { '戦闘開始時発動' => '战斗开始时发动', 'ターン終了時発動' => '回合结束时发动', 'オートステート' => '自动状态', '反撃スキル' => '反击技能' }[tag]
        return [record(tag, tag, zh_label, 'dynamic', body, '', 'note', "<#{content}>")]
      when 'オートステート'
        # Auto states are applied when battle starts; list the actual state names.
        ids = body.scan(/\d+/)
        return [] if ids.empty?
        names_jp = ids.map { |id| lookup(lookups[:states], id, '状态') }
        names_zh = names_jp.map { |name| translate_name(name) }
        jp = "戦闘開始時に#{names_jp.join('、')}（ステートID #{ids.join('、')}）を自動付与"
        zh = "战斗开始时自动附加#{names_zh.join('、')}（状态ID #{ids.join('、')}）"
        return [record(tag, jp, zh, 'id_list', ids.join(','), '', 'note', "<#{content}>")]
      when '開始時TP'
        value = body[/[+-]?\d+(?:\.\d+)?%/]
        return [] unless value
        number = value.sub(/\z/, '')
        jp = "戦闘開始時SPは#{number}"
        zh = "战斗开始时SP为#{number}"
        return [record(tag, jp, zh, numeric_value_type(tag), number.delete('%'), "+#{number}", 'note', "<#{content}>")]
      end

      explanation = GouqiActorPassiveExplainer.explain_tag(tag, content, lookups)
      return [] unless explanation
      jp_lines = Array(explanation[0]).flatten
      zh_lines = Array(explanation[1]).flatten
      jp_lines.each_with_index.map do |jp, index|
        zh = zh_lines[index].to_s
        raw_value = extract_numeric_value(tag, body, index)
        record(tag, jp, zh, numeric_value_type(tag), raw_value,
               numeric_value_display(tag, raw_value), 'note', "<#{content}>")
      end
    end

    # These note types are parsed into a Hash by the game, so later values replace earlier values for the same ID.
    def normalize_hash_pair_note(tag, body, lookups)
      return [body, nil] unless HASH_PAIR_NOTE_TAGS.include?(tag)

      pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
      return [body, nil] if pairs.empty?

      order = []
      values = {}
      history = Hash.new { |hash, key| hash[key] = [] }
      pairs.each do |id, amount|
        order << id unless values.key?(id)
        history[id] << amount
        values[id] = amount
      end
      duplicate_ids = order.select { |id| history[id].length > 1 }
      return [body, nil] if duplicate_ids.empty?

      normalized_body = order.map { |id| "#{id}-#{values[id]}" }.join(',')
      details = duplicate_ids.map do |id|
        amounts = history[id]
        if tag == '属性強化'
          element = translate_name(element_lookup(lookups[:elements], id))
          "属性ID #{id}重复设置为#{amounts.map { |amount| "#{amount}%" }.join('和')}；游戏按备注中的最后一个值计算，因此实际为#{element}属性强化+#{values[id]}%"
        else
          "ID #{id}重复设置为#{amounts.map { |amount| "#{amount}%" }.join('和')}；游戏按备注中的最后一个值#{values[id]}%计算"
        end
      end
      [normalized_body, details.join('；') + '。']
    end

    def append_record_comment(records, comment)
      return records if comment.to_s.empty?

      records.each do |item|
        existing = item[:comment].to_s
        item[:comment] = if existing.empty?
                           comment
                         elsif existing.end_with?('。', '！', '？', '；')
                           "#{existing}#{comment}"
                         else
                           "#{existing}；#{comment}"
                         end
      end
      records
    end

    def auto_skill_condition_text(condition_type, condition_ids, lookups)
      return nil unless condition_type && !condition_ids.empty?

      case condition_type
      when 1
        ids = condition_ids.join('、')
        ["味方に指定アクター（ID #{ids}）がいる時", "己方存在指定角色（角色ID #{ids}）时"]
      when 2
        ids = condition_ids.join('、')
        ["敵に指定エネミー（ID #{ids}）がいる時", "敌方存在指定敌人（敌人ID #{ids}）时"]
      when 3
        ["味方に状態異常または能力低下がある時", "己方存在异常状态或能力下降时"]
      when 4
        if condition_ids.length == 1
          state = lookup(lookups[:states], condition_ids.first, '状态')
          state_zh = normalize_state_name_zh(translate_name(state))
          ["敵に「#{state}」がある時", "敌方存在「#{state_zh}」状态时"]
        elsif condition_ids.all? { |id| id >= 300 }
          ["敵に強化状態がある時", "敌方存在强化状态时"]
        else
          ids = condition_ids.join('、')
          ["敵に指定状態（ID #{ids}）がある時", "敌方存在指定状态（状态ID #{ids}）时"]
        end
      when 5
        ["自身に状態異常または能力低下がある時", "自身存在异常状态或能力下降时"]
      else
        ids = condition_ids.join('、')
        ["指定条件（类型#{condition_type}、ID #{ids}）成立時", "指定条件（类型#{condition_type}、ID #{ids}）成立时"]
      end
    end

    def parse_stat_replacement(body)
      match = body.match(/\A(?:\[((?:\d+\s*,?\s*)+)\]|(\d+))\s*,\s*(\d+)\s*,\s*(\d+)\z/)
      return nil unless match

      stype_ids = (match[1] || match[2]).scan(/\d+/).map(&:to_i)
      return nil if stype_ids.empty?

      [stype_ids, match[3].to_i, match[4].to_i]
    end

    def parse_stat_addition(body)
      match = body.match(/\A(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([+-]?\d+(?:\.\d+)?)\z/)
      return nil unless match

      [match[1].to_i, match[2].to_i, match[3].to_i, match[4].to_f]
    end

    def ability_value_names(id)
      names = ABILITY_VALUE_NAMES[id.to_i]
      return names if names

      fallback = "能力值ID #{id}"
      [fallback, fallback]
    end

    def skill_type_names(ids, lookups, chinese)
      names = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
      names = names.map { |name| chinese ? translate_name(name) : name }
      names.join('、')
    end

    def stat_rate_text(rate)
      number(rate)
    end

    def summarize_long_note(actor_id, tag, body, lookups, content)
      fixed_summary = summarize_fixed_long_note(actor_id, tag, body, lookups, content)
      return fixed_summary if fixed_summary

      category_skill_summary = summarize_special_category_skill_type(actor_id, tag, body, lookups, content)
      return category_skill_summary if category_skill_summary

      party_summary = summarize_party_actor_list(actor_id, tag, body, lookups, content)
      return party_summary if party_summary

      skill_list_summary = summarize_uniform_skill_list(actor_id, tag, body, lookups, content)
      return skill_list_summary if skill_list_summary

      grouped_pair_summary = summarize_grouped_pair_note(actor_id, tag, body, lookups, content)
      return grouped_pair_summary if grouped_pair_summary

      named_list_summary = summarize_uniform_named_list(actor_id, tag, body, lookups, content)
      return named_list_summary if named_list_summary

      no_cost_summary = summarize_long_no_cost(actor_id, tag, body, lookups, content)
      return no_cost_summary if no_cost_summary

      skill_state_summary = summarize_uniform_skill_state_addition(actor_id, tag, body, lookups, content)
      return skill_state_summary if skill_state_summary

      type_state_summary = summarize_long_type_state_addition(tag, body, lookups, content)
      return type_state_summary if type_state_summary

      if ['ステート特攻スキルタイプ', 'ステート特攻スキル'].include?(tag)
        return summarize_long_state_attack(actor_id, tag, body, lookups, content)
      end

      supported_tags = [
        'スキル強化', 'スキルタイプ強化', '窮地スキル強化', '窮地スキルタイプ強化',
        'ステート割合強化スキル', 'HPスキル消費率', 'MPスキル消費率', 'TPスキル消費率',
        'HPタイプ消費率', 'MPタイプ消費率', 'TPタイプ消費率', '連続発動スキル',
        '連続発動タイプ', 'パーティ特定アクター能力アップ'
      ]
      return nil unless supported_tags.include?(tag)

      pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
      return nil if pairs.length < LONG_LIST_THRESHOLD
      values = pairs.map { |_id, value| value }
      return nil unless values.uniq.length == 1

      value = values.first
      target_jp, target_zh = long_target_labels(actor_id, tag, pairs, lookups)
      case tag
      when 'スキル強化'
        display = "+#{value}%"
        jp = "#{target_jp}威力 #{display}"
        zh = "#{target_zh}威力 #{display}"
        value_type = 'additive_percent'
      when 'スキルタイプ強化'
        display = "+#{value}%"
        jp = "#{target_jp}の威力 #{display}"
        zh = "#{target_zh}强化 #{display}"
        value_type = 'additive_percent'
      when '窮地スキル強化'
        display = "+#{value}%"
        jp = "瀕死時、#{target_jp}威力 #{display}"
        zh = "濒死时#{target_zh}威力 #{display}"
        value_type = 'additive_percent'
      when '窮地スキルタイプ強化'
        display = "+#{value}%"
        jp = "瀕死時、#{target_jp}の威力 #{display}"
        zh = "濒死时#{target_zh}强化 #{display}"
        value_type = 'additive_percent'
      when 'ステート割合強化スキル'
        display = "+#{value}%"
        jp = "#{target_jp}の状態異常付加率 #{display}"
        zh = "#{target_zh}的异常状态附加率 #{display}"
        value_type = 'additive_percent'
      when 'HPスキル消費率', 'MPスキル消費率', 'TPスキル消費率',
           'HPタイプ消費率', 'MPタイプ消費率', 'TPタイプ消費率'
        cost_type = tag[0, 2]
        display = multiplier_display(value)
        jp = "#{target_jp}の#{cost_type}消費量#{percent_ratio_phrase_jp(value)}"
        zh = "#{target_zh}#{cost_type}消耗量#{percent_ratio_phrase_zh(value)}"
        value_type = 'multiplier'
      when '連続発動スキル', '連続発動タイプ'
        display = "#{value}次"
        jp = "#{target_jp}を#{display}連続発動"
        zh = "#{target_zh}连续发动#{display}"
        value_type = 'count'
      when 'パーティ特定アクター能力アップ'
        display = "+#{value}%"
        jp = "#{target_jp}がパーティにいる時、能力 #{display}"
        zh = "#{target_zh}在队伍中时能力强化 #{display}#{PARTY_ACTOR_ABILITY_SUFFIX}"
        value_type = 'additive_percent'
      end
      item = record(tag, jp, zh, value_type, value, display, 'note', "<#{content}>")
      if actor_id == 4 && tag == '窮地スキルタイプ強化' && body == '7-200,26-200,27-200,48-200,70-200'
        item[:comment] = '该备注中的勇者技（技能类型ID 48）与角色4另一条<窮地スキルタイプ強化 48-200>备注重复，另一条同样为+200%。游戏对同一技能类型的濒死强化取最高值，不会叠加，因此勇者技实际仍为濒死时强化+200%，不是+400%。'
      end
      item[:comment] = summarized_target_comment(tag, target_zh, pairs.map(&:first), lookups)
      [item]
    end

    # Keep one source note on one CSV row while grouping targets that share the same value.
    def summarize_grouped_pair_note(actor_id, tag, body, lookups, content)
      supported_tags = [
        'スキルタイプ強化', '属性強化', 'ステート割合強化タイプ',
        '消費アイテム節約スキルタイプ', 'スキルタイプ攻撃回数アップ',
        '特殊カテゴリー与ダメージアップ', '特殊カテゴリー被ダメージダウン'
      ]
      return nil unless supported_tags.include?(tag)

      pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
      return nil if pairs.length < 2

      groups = []
      pairs.each do |id, value|
        group = groups.find { |entry| entry[:value] == value }
        unless group
          group = { :value => value, :ids => [] }
          groups << group
        end
        group[:ids] << id unless group[:ids].include?(id)
      end

      jp_clauses = []
      zh_clauses = []
      groups.each do |group|
        value = group[:value]
        ids = group[:ids]
        case tag
        when 'スキルタイプ強化'
          names_jp = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
          names_zh = ids.map { |id| skill_type_effect_name_zh(lookups[:skill_types], id) }
          jp_clauses << "#{names_jp.join('・')}の威力 +#{value}%"
          zh_clauses << "#{names_zh.join('、')}强化 +#{value}%"
        when '属性強化'
          names_jp = ids.map { |id| element_lookup(lookups[:elements], id) }
          names_zh = names_jp.map { |name| translate_name(name) }
          jp_clauses << "#{named_category_phrase(names_jp.join('・'), '属性', 'の威力')} +#{value}%"
          zh_clauses << "#{named_category_phrase(names_zh.join('、'), '属性', '威力')} +#{value}%"
        when 'ステート割合強化タイプ'
          names_jp = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
          names_zh = ids.map { |id| skill_type_effect_name_zh(lookups[:skill_types], id) }
          jp_clauses << "#{names_jp.join('・')}のステート付与率#{percent_change_phrase_jp(value)}"
          zh_clauses << "#{names_zh.join('、')}的状态附加率#{percent_change_phrase_zh(value)}"
        when '消費アイテム節約スキルタイプ'
          names_jp = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
          names_zh = ids.map { |id| skill_type_effect_name_zh(lookups[:skill_types], id) }
          jp_clauses << "#{names_jp.join('・')}使用時、#{value}%の確率で消費アイテムを節約"
          zh_clauses << "使用#{names_zh.join('或')}时，#{value}%概率不消耗道具"
        when 'スキルタイプ攻撃回数アップ'
          names_jp = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
          names_zh = ids.map { |id| skill_type_effect_name_zh(lookups[:skill_types], id) }
          jp_clauses << "#{names_jp.join('・')}の攻撃回数 +#{value}"
          zh_clauses << "#{names_zh.join('、')}攻击次数 +#{value}"
        when '特殊カテゴリー与ダメージアップ'
          names_jp = ids.map { |id| ex_category_names(id)[0] }
          names_zh = ids.map { |id| ex_category_names(id)[1] }
          jp_clauses << "#{names_jp.join('・')}への特攻 +#{value}%"
          zh_clauses << "对#{names_zh.join('、')}特攻 +#{value}%"
        when '特殊カテゴリー被ダメージダウン'
          names_jp = ids.map { |id| ex_category_names(id)[0] }
          names_zh = ids.map { |id| ex_category_names(id)[1] }
          jp_clauses << "#{names_jp.join('・')}から受けるダメージを#{value}%軽減"
          zh_clauses << "受到#{names_zh.join('、')}的伤害降低#{value}%"
        end
      end

      uniform = groups.length == 1
      value_type = if uniform
                     case tag
                     when '消費アイテム節約スキルタイプ' then 'chance'
                     when 'スキルタイプ攻撃回数アップ' then 'count'
                     else 'additive_percent'
                     end
                   else
                     'mapping'
                   end
      value_raw = uniform ? groups.first[:value] : pairs.map { |id, value| "#{id}-#{value}" }.join(',')
      value_display = if uniform
                        case tag
                        when '消費アイテム節約スキルタイプ' then "#{groups.first[:value]}%"
                        when 'スキルタイプ攻撃回数アップ' then "+#{groups.first[:value]}"
                        else "+#{groups.first[:value]}%"
                        end
                      else
                        ''
                      end
      item = record(tag, jp_clauses.join('；'), zh_clauses.join('；'),
                    value_type, value_raw, value_display, 'note', "<#{content}>")
      if tag == 'スキルタイプ強化' && content == 'スキルタイプ強化 9-25,18-26,29-25,37-25,49-25'
        item[:comment] = '原备注中只有扇技为26%，其余技能类型均为25%；可能是原数据笔误，但游戏实际按26%计算。'
      elsif tag == 'スキルタイプ強化' && pairs.any? { |id, _value| id == '64' }
        item[:comment] = '技能类型ID 64「装备武器」指由装备武器提供的技能，不是直接提高武器装备属性。'
      elsif actor_id == 627 && tag == '属性強化' && pairs.any? { |id, _value| id == '68' }
        item[:comment] = '固有能力说明写成「魔技」「妖术」威力大幅提升，但原始备注误用了属性强化标签<属性強化 50-50,68-50>。技能类型ID 50「魔技」被当作属性ID后，实际变成终焉属性威力 +50%；技能类型ID 68「妖术」没有对应的属性ID，因此68-50无法作为属性强化生效。结果是魔技和妖术的技能威力强化均未生效。'
      elsif actor_id == 398 && tag == '属性強化' && pairs.include?(['1', '50']) && pairs.include?(['41', '50'])
        item[:comment] = '固有能力描述写的是物理、重力属性攻击威力提升，但原始备注<属性強化 1-50,41-50>实际指定了物理属性（ID 1）和银河属性（ID 41）。因此银河属性这一项与固有能力描述不一致，很可能是作者将重力属性ID 40误写成了银河属性ID 41；当前应以原始备注的实际效果为准。'
      elsif actor_id == 845 && tag == '属性強化' && pairs == [['10', '49'], ['10', '50']]
        item[:comment] = '原始备注为<属性強化 10-49,10-50>，当前实际解析为暗属性强化49%与暗属性强化50%；这与固有能力描述中的永劫、终焉属性强化不符。作者可能原本想写永劫属性强化50%与终焉属性强化50%，但该推测需以原始数据或实测为准。'
      elsif actor_id == 998 && tag == 'スキルタイプ強化' && pairs == [['7', '50'], ['10', '50'], ['21', '50'], ['20', '50']]
        item[:comment] = '固有能力描述写成「剑技」「枪技」「格斗」「吐息」威力提升，但原始备注实际指定的是剑技、枪技、格斗、多武器技各+50%；其中多武器技取代了描述中的吐息。角色本身不能使用枪技，因此枪技强化当前无法发挥；剑技、格斗和多武器技强化可以发挥。'
      elsif tag == '特殊カテゴリー被ダメージダウン' && pairs.map(&:first).uniq.length > 1
        item[:comment] = '攻击者同时属于多个列出的种族时，各种族的受伤倍率分别生效并相乘。'
      end
      [item]
    end

    # Group one special-category note by equivalent skill-type/category mappings.
    # This keeps one source tag on one CSV row while preserving non-cartesian mappings.
    def summarize_special_category_skill_type(actor_id, tag, body, lookups, content)
      return nil unless tag == '特殊カテゴリー与ダメージアップスキルタイプ'

      triples = body.scan(/(\d+)\s*-\s*(\d+)\s*-\s*([+-]?\d+)/)
      return nil if triples.length < 2

      # Actor 40 has three duplicated gun mappings in the original note. The
      # fixed semantic override below documents the intended non-cartesian rule.
      return nil if actor_id == 40

      ordered_groups = []
      triples.each do |stype_id, category_id, amount|
        key = [amount, category_id]
        group = ordered_groups.find { |entry| entry[:key] == key }
        unless group
          group = { :key => key, :stype_ids => [], :category_id => category_id }
          ordered_groups << group
        end
        group[:stype_ids] << stype_id unless group[:stype_ids].include?(stype_id)
      end

      clauses = ordered_groups.map do |group|
        amount, category_id = group[:key]
        stype_jp = group[:stype_ids].map { |id| skill_type_lookup(lookups[:skill_types], id) }.join('・')
        stype_zh = group[:stype_ids].map { |id| translate_name(skill_type_lookup(lookups[:skill_types], id)) }.join('、')
        category_jp, category_zh = ex_category_names(category_id)
        {
          :amount => amount,
          :stype_ids => group[:stype_ids],
          :category_id => category_id,
          :jp => "「#{stype_jp}」で#{category_jp}に特攻ダメージ +#{amount}%",
          :zh => "使用「#{stype_zh}」时，对#{category_zh}特攻伤害 +#{amount}%"
        }
      end

      amounts = clauses.map { |clause| clause[:amount] }.uniq
      value_type = amounts.length == 1 ? 'additive_percent' : 'mapping'
      value_raw = amounts.length == 1 ? amounts.first : triples.map { |stype, category, amount| "#{stype}-#{category}-#{amount}" }.join(',')
      value_display = amounts.length == 1 ? "+#{amounts.first}%" : ''
      item = record(tag, clauses.map { |clause| clause[:jp] }.join('；'),
                    clauses.map { |clause| clause[:zh] }.join('；'), value_type, value_raw,
                    value_display, 'note', "<#{content}>")
      item[:comment] = clauses.map do |clause|
        stypes = id_name_entries(clause[:stype_ids], lookups[:skill_types], '技能类型')
        category_id = clause[:category_id]
        category_name = ex_category_names(category_id)[1]
        "技能类型：#{stypes}；种族：#{category_id}（#{category_name}）"
      end.join('；')
      [item]
    end

    def summarize_party_actor_list(actor_id, tag, body, lookups, content)
      return nil unless tag == 'パーティ特定アクター能力アップ'

      pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
      return nil if pairs.length < 2

      values = pairs.map(&:last)
      return nil unless values.uniq.length == 1

      groups = []
      pairs.each do |target_id, amount|
        name_jp = lookup(lookups[:actors], target_id, '角色')
        name_zh = actor_name_chinese(lookups[:actors], target_id)
        group = groups.find { |entry| entry[:name_zh] == name_zh }
        unless group
          group = { :name_jp => name_jp, :name_zh => name_zh, :ids => [] }
          groups << group
        end
        group[:ids] << target_id
      end

      value = values.first
      display = "+#{value}%"
      if actor_id == 60
        target_jp = '魔獣系モンスター'
        target_zh = '兽族伙伴'
      else
        target_jp = groups.map { |group| group[:name_jp] }.join('、')
        target_zh = groups.map { |group| group[:name_zh] }.join('、')
      end
      item = record(tag,
                    "#{target_jp}がパーティにいる時、能力 #{display}",
                    "#{target_zh}在队伍中时能力强化 #{display}#{PARTY_ACTOR_ABILITY_SUFFIX}",
                    'additive_percent', value, display, 'note', "<#{content}>")
      item[:comment] = "对应角色：#{party_actor_group_entries(groups)}"
      [item]
    end

    def party_actor_group_entries(groups)
      groups.map do |group|
        ids = group[:ids].join('、')
        "#{ids}（#{group[:name_zh]}）"
      end.join('、')
    end

    # Keep one source note as one record when several skills share the same state effect.
    def summarize_uniform_skill_state_addition(actor_id, tag, body, lookups, content)
      return nil unless ['スキルステート付加', 'スキルステート自己付加'].include?(tag)

      triples = body.scan(/(\d+)\s*-\s*(\d+)\s*-\s*([+-]?\d+)/)
      return nil if triples.length < 2

      groups = triples.group_by { |_skill_id, state_id, amount| [state_id, amount] }
      self_target = tag.include?('自己')
      subject_jp = self_target ? '自身' : (actor_id == 451 ? '蘇生対象' : 'スキル対象')
      subject_zh = self_target ? '自身' : (actor_id == 451 ? '复活目标' : '技能目标')
      descriptions_jp = groups.map do |(state_id, amount), entries|
        names = entries.map { |skill_id, _state, _value| skill_lookup(lookups[:skills], skill_id) }
        state = lookup(lookups[:states], state_id, '状态')
        if self_target
          "#{names.join('、')}使用時、自身に「#{state}」効果を#{amount}%の確率で付与"
        else
          "#{names.join('、')}使用時、#{subject_jp}に「#{state}」を#{amount}%の確率で付与"
        end
      end
      descriptions_zh = groups.map do |(state_id, amount), entries|
        names = entries.map { |skill_id, _state, _value| translate_name(skill_lookup(lookups[:skills], skill_id)) }
        state = state_name_zh(lookups, state_id)
        if self_target
          "使用#{names.join('、')}时，以#{amount}%概率赋予自身「#{self_state_effect_zh(state)}」效果"
        else
          "使用#{names.join('、')}时，以#{amount}%概率对#{subject_zh}附加「#{state}」状态"
        end
      end
      values = triples.map { |_skill_id, _state_id, amount| amount }
      uniform = values.uniq.length == 1
      value_raw = uniform ? values.first : triples.map { |skill_id, state_id, amount| "#{skill_id}-#{state_id}-#{amount}" }.join(',')
      item = record(tag, descriptions_jp.join('；'), descriptions_zh.join('；'), uniform ? 'chance' : 'mapping', value_raw, uniform ? "#{values.first}%" : '', 'note', "<#{content}>")
      item[:zh] = normalize_self_state_description(item[:zh]) if self_target
      item[:comment] = state_effect_comment(tag, triples, lookups) if groups.length > 1 || item[:zh].length > INLINE_DESCRIPTION_LIMIT
      [item]
    end

    def summarize_uniform_skill_list(actor_id, tag, body, lookups, content)
      supported_tags = [
        'スキル強化', 'HPスキル消費率', 'MPスキル消費率', 'TPスキル消費率',
        '連続発動スキル', 'ステート割合強化スキル'
      ]
      return nil unless supported_tags.include?(tag)

      pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
      ids = pairs.map(&:first).uniq
      values = pairs.map { |_id, value| value }
      return nil if ids.length < 2
      return nil unless values.uniq.length == 1

      names_jp = ids.map { |id| skill_lookup(lookups[:skills], id) }
      names_zh = names_jp.map { |name| translate_name(name) }
      target_jp = names_jp.join('・')
      target_zh = names_zh.join('、')
      value = values.first

      case tag
      when 'スキル強化'
        display = "+#{value}%"
        jp = "#{target_jp}の威力 #{display}"
        zh = "#{target_zh}威力 #{display}"
        value_type = 'additive_percent'
      when 'HPスキル消費率', 'MPスキル消費率', 'TPスキル消費率'
        cost_type = tag[0, 2]
        display = multiplier_display(value)
        jp = "#{target_jp}の#{cost_type}消費量#{percent_ratio_phrase_jp(value)}"
        zh = "#{target_zh}#{cost_type}消耗量#{percent_ratio_phrase_zh(value)}"
        value_type = 'multiplier'
      when '連続発動スキル'
        display = "#{value}次"
        jp = "#{target_jp}を#{display}連続発動"
        zh = "#{target_zh}连续发动#{display}"
        value_type = 'count'
      when 'ステート割合強化スキル'
        display = "+#{value}%"
        jp = "#{target_jp}の状態異常付加率 #{display}"
        zh = "#{target_zh}的异常状态附加率 #{display}"
        value_type = 'additive_percent'
      end

      item = record(tag, jp, zh, value_type, value, display, 'note', "<#{content}>")
      if actor_id == 448 && tag == 'TPスキル消費率'
        item[:comment] = '固有能力说明写成使用粘丝的技能SP消耗变为1/5（20%），但原始备注实际只指定了10个具体技能，且这些技能的SP消耗量均变为50%（减少50%），并非20%（减少80%）；因此消耗倍率和适用范围都与固有能力说明不一致。'
      end
      return [item] if item[:zh].length <= INLINE_DESCRIPTION_LIMIT

      fallback_jp, fallback_zh = LONG_TARGET_OVERRIDES.fetch(
        [actor_id, tag],
        ["指定された#{ids.length}個のスキル", "指定的#{ids.length}个技能"]
      )
      case tag
      when 'スキル強化'
        item[:jp] = "#{fallback_jp}の威力 #{display}"
        item[:zh] = "#{fallback_zh}威力 #{display}"
      when 'HPスキル消費率', 'MPスキル消費率', 'TPスキル消費率'
        cost_type = tag[0, 2]
        item[:jp] = "#{fallback_jp}の#{cost_type}消費量#{percent_ratio_phrase_jp(value)}"
        item[:zh] = "#{fallback_zh}#{cost_type}消耗量#{percent_ratio_phrase_zh(value)}"
      when '連続発動スキル'
        item[:jp] = "#{fallback_jp}を#{display}連続発動"
        item[:zh] = "#{fallback_zh}连续发动#{display}"
      when 'ステート割合強化スキル'
        item[:jp] = "#{fallback_jp}の状態異常付加率 #{display}"
        item[:zh] = "#{fallback_zh}的异常状态附加率 #{display}"
      end
      item[:comment] = "技能：#{id_name_entries(ids, lookups[:skills], '技能')}"
      if actor_id == 448 && tag == 'TPスキル消費率'
        item[:comment] = '固有能力说明写成使用粘丝的技能SP消耗变为1/5（20%），但原始备注实际只指定了10个具体技能，且这些技能的SP消耗量均变为50%（减少50%），并非20%（减少80%）；因此消耗倍率和适用范围都与固有能力说明不一致。'
      end
      [item]
    end

    def summarize_uniform_named_list(actor_id, tag, body, lookups, content)
      supported_tags = [
        'スキルタイプ強化', 'HPタイプ消費率', 'MPタイプ消費率', 'TPタイプ消費率',
        '属性強化', '窮地スキルタイプ強化', '連続発動タイプ'
      ]
      return nil unless supported_tags.include?(tag)

      pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
      ids = pairs.map(&:first).uniq
      values = pairs.map { |_id, value| value }
      return nil if ids.length < 2
      return nil unless values.uniq.length == 1

      collection = tag == '属性強化' ? lookups[:elements] : lookups[:skill_types]
      fallback = tag == '属性強化' ? '属性' : '技能类型'
      names_jp = ids.map { |id| tag == '属性強化' ? element_lookup(collection, id) : skill_type_lookup(collection, id) }
      names_zh = names_jp.map { |name| translate_name(name) }
      target_jp = names_jp.join('・')
      target_zh = names_zh.join('、')
      value = values.first

      case tag
      when 'スキルタイプ強化'
        display = "+#{value}%"
        jp = "#{target_jp}の威力 #{display}"
        zh = "#{target_zh}强化 #{display}"
        value_type = 'additive_percent'
      when '属性強化'
        display = "+#{value}%"
        jp = "#{named_category_phrase(target_jp, '属性', 'の威力')} #{display}"
        zh = "#{named_category_phrase(target_zh, '属性', '威力')} #{display}"
        value_type = 'additive_percent'
      when '窮地スキルタイプ強化'
        display = "+#{value}%"
        jp = "瀕死時、#{target_jp}の威力 #{display}"
        zh = "濒死时#{target_zh}强化 #{display}"
        value_type = 'additive_percent'
      when 'HPタイプ消費率', 'MPタイプ消費率', 'TPタイプ消費率'
        cost_type = tag[0, 2]
        display = multiplier_display(value)
        jp = "#{target_jp}の#{cost_type}消費量#{percent_ratio_phrase_jp(value)}"
        zh = "#{target_zh}#{cost_type}消耗量#{percent_ratio_phrase_zh(value)}"
        value_type = 'multiplier'
      when '連続発動タイプ'
        display = "#{value}次"
        jp = "#{target_jp}を#{display}連続発動"
        zh = "#{target_zh}连续发动#{display}"
        value_type = 'count'
      end

      item = record(tag, jp, zh, value_type, value, display, 'note', "<#{content}>")
      if actor_id == 728 && tag == 'TPタイプ消費率' && ids.sort == %w[26 53]
        item[:comment] = '实际标签使圣技（ID 26）和兽技的SP消耗量变为133%（增加33%）。但上一条标签的连续发动对象是神谕（ID 36）和兽技，因此这里很可能是作者将神谕的ID 36误写成了圣技的ID 26。角色已通过种族获得圣技使用权限，但初始状态没有学会任何圣技技能，因此当前没有可用的圣技。'
      end
      if actor_id == 571 && tag == 'TPタイプ消費率' && ids.sort == ['18'] && value.to_f == 66.0
        item[:comment] = '固有能力说明写成「海贼技」「跳舞」的SP消耗量变为约2/3，但原始备注实际分别指定海贼技（ID 32）和扇技（ID 18）的SP消耗量变为66%（减少34%），没有配置舞蹈（ID 37）的减耗效果。作者很可能将舞蹈的技能类型ID 37误写成了扇技的ID 18。角色本身不能使用扇技，因此扇技减耗部分通常无法发挥作用；海贼技减耗部分可以正常生效。'
      end
      if actor_id == 442 && tag == 'TPタイプ消費率' && ids.sort == %w[15 58] && value.to_f == 66.0
        item[:comment] = '固有能力说明写成「鞭技」「植物技」SP消耗减半（50%），但原始备注<TPタイプ消費率 15-66,58-66>实际使鞭技和植物技的SP消耗量均变为66%（减少34%），不是减半。'
      end
      if [33, 35].include?(actor_id) && tag == 'HPタイプ消費率'
        item[:zh] = "使用#{target_zh}时，HP消耗量#{percent_ratio_phrase_zh(value)}"
        item[:comment] = "技能类型：#{id_name_entries(ids, collection, fallback)}"
        if actor_id == 33
          item[:comment] = [
            item[:comment],
            '“暗属性技能HP消耗减少50%”的概括并不准确；该能力按技能类型而非攻击属性判定，因此含暗属性的歌唱技能也不会获得减耗'
          ].join('；')
        end
        return [item]
      end
      return [item] if item[:zh].length <= INLINE_DESCRIPTION_LIMIT

      fallback_jp, fallback_zh = summarized_named_list_target(actor_id, tag, ids.length)
      case tag
      when 'スキルタイプ強化'
        item[:jp] = "#{fallback_jp}の威力 #{display}"
        item[:zh] = "#{fallback_zh}强化 #{display}"
      when '属性強化'
        item[:jp] = "#{fallback_jp}の威力 #{display}"
        item[:zh] = "#{fallback_zh}威力 #{display}"
      when '窮地スキルタイプ強化'
        item[:jp] = "瀕死時、#{fallback_jp}の威力 #{display}"
        item[:zh] = "濒死时#{fallback_zh}强化 #{display}"
      when 'HPタイプ消費率', 'MPタイプ消費率', 'TPタイプ消費率'
        cost_type = tag[0, 2]
        item[:jp] = "#{fallback_jp}の#{cost_type}消費量#{percent_ratio_phrase_jp(value)}"
        item[:zh] = "#{fallback_zh}#{cost_type}消耗量#{percent_ratio_phrase_zh(value)}"
      when '連続発動タイプ'
        item[:jp] = "#{fallback_jp}を#{display}連続発動"
        item[:zh] = "#{fallback_zh}连续发动#{display}"
      end
      item[:comment] = if tag == '属性強化'
                         "属性：#{id_name_entries(ids, collection, fallback)}"
                       else
                         "技能类型：#{id_name_entries(ids, collection, fallback)}"
                       end
      [item]
    end

    def summarized_named_list_target(actor_id, tag, count)
      return ["指定された#{count}属性", "指定的#{count}种属性"] if tag == '属性強化'

      override = LONG_TARGET_OVERRIDES[[actor_id, tag]]
      return override if override
      ["指定された#{count}種類のスキル", "指定的#{count}类技能"]
    end

    def summarize_fixed_long_note(actor_id, tag, body, lookups, content)
      if actor_id == 525 && tag == '窮地スキル強化' && body.match?(/\A\s*12\s*-\s*100\s*\z/)
        item = record(tag,
                      '瀕死時、スキルID 12「ぶんどる」（スキルタイプなし）強化 +100%',
                      '濒死时技能ID 12「抢夺」（无技能类型）强化 +100%',
                      'additive_percent', '100', '+100%', 'note', "<#{content}>")
        item[:comment] = '作者原本应写<窮地スキルタイプ強化 12-100>（濒死时强化技能类型12「棍技」），却误写成了<窮地スキル強化 12-100>，导致12被按技能ID解析为不属于任何技能类型的「ぶんどる（抢夺）」，正常情况下不可用；此形态下该濒死强化效果不生效。'
        return [item]
      end

      if tag == 'パーティ特定アクター能力アップ'
        pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
        ids = pairs.map(&:first)
        values = pairs.map(&:last)
        if ids == %w[26 27 28 34 36] && values.uniq.length == 1
          value = values.first
          display = "+#{value}%"
          item = record(tag,
                        '正史イリアス、ミカエラちゃん、ルシフィナちゃんがパーティにいる時、能力 ' + display,
                        '队伍中有正史伊莉娅丝、小米迦艾拉或小路西菲娜时，能力强化 ' + display + PARTY_ACTOR_ABILITY_SUFFIX,
                        'additive_percent', value, display, 'note', "<#{content}>")
          item[:comment] = '对应角色：26（创世小女神）、27（创世女神）、28（创世混沌女神）、34（小米迦艾拉）、36（小路西菲娜）；26、27、28合并为正史伊莉娅丝。'
          return [item]
        end
      end

      if actor_id == 131 && tag == '窮地スキル強化'
        pairs = body.scan(/(\d+)\s*-\s*([+-]?\d+)/)
        values = pairs.map(&:last)
        return nil if pairs.length < 2 || values.uniq.length != 1

        value = values.first
        display = "+#{value}%"
        item = record(tag, "瀕死時、髪を用いたスキルの威力 #{display}",
                      "濒死时使用头发的技能威力 #{display}",
                      'additive_percent', value, display, 'note', "<#{content}>")
        item[:comment] = "技能：#{id_name_entries(pairs.map(&:first), lookups[:skills], '技能')}"
        return [item]
      end

      triples = body.scan(/(\d+)\s*-\s*(\d+)\s*-\s*([+-]?\d+)/)
      short_semantic_override = [131, '窮地スキル強化'] == [actor_id, tag]
      return nil if triples.length < LONG_LIST_THRESHOLD && !short_semantic_override
      values = triples.map { |_first, _second, value| value }
      return nil unless values.uniq.length == 1

      value = values.first
      source = "<#{content}>"
      if actor_id == 40 && tag == '特殊カテゴリー与ダメージアップスキルタイプ'
        display = "+#{value}%"
        gun_display = "+#{value.to_i * 3}%"
        jp = "「銃技」でキメラに特攻ダメージ #{gun_display}；「魔導科学」「マキナ」「医術」「造技」でキメラ・巨人・ロイドに特攻ダメージ #{display}"
        zh = "使用「铳技」时，对奇美拉造成特攻伤害 #{gun_display}；使用「魔导科学」「器械」「医术」「造技」时，对奇美拉、巨人和机器人造成特攻伤害 #{display}"
        item = record(tag, jp, zh, 'additive_percent', value, display, 'note', source)
        item[:comment] = '适用组合：技能类型19（铳技）→种族33（奇美拉）；技能类型40（魔导科学）、43（器械）、45（医术）、60（造技）→种族33（奇美拉）、37（巨人）、38（机器人）。原标签中的19-33-100出现3次，游戏脚本会将同一组合的特攻增幅累加，因此铳技对奇美拉实际为+300%，对应特攻倍率为×4.0；其他组合各为+100%。'
        return [item]
      end

      display = "#{value}%"
      case [actor_id, tag]
      when [131, '窮地スキル強化']
        jp = "瀕死時、髪を用いたスキルの威力 +#{display}"
        zh = "濒死时使用头发的技能威力 +#{display}"
      when [275, 'スキルステート自己付加']
        jp = "魔法剣に属する剣技を使用すると、自身に対応する属性の魔法剣効果を付与（#{display}）"
        zh = "使用魔法剑类剑技时，为自身附加对应属性的魔法剑效果（#{display}）"
      when [461, 'スキルステート付加']
        jp = "「医術」に属する回復スキルに全能力アップ効果を付加（#{display}）"
        zh = "使用「医术」中的恢复技能时，附加全能力提升效果（#{display}）"
      when [669, 'スキルタイプステート敵付加']
        jp = "「ブレス」で毒・暗闇・沈黙・混乱・睡眠・麻痺・敏感・恍惚・誘惑・失禁を各#{display}で付与"
        zh = "使用「吐息」时，分别以#{display}概率附加中毒、黑暗、沉默、混乱、睡眠、麻痹、敏感、恍惚、诱惑和失禁"
      when [758, 'スキルタイプステート敵付加']
        jp = "「鎌技」「陰陽術」「忍術」「料理」「屍技」でフリーズ・ゾンビ・闇穢を各#{display}で付与"
        zh = "使用「镰技」「阴阳术」「忍术」「料理」「尸技」时，分别以#{display}概率附加冻结、僵尸和暗秽"
      else
        return nil
      end
      item = record(tag, jp, zh, 'chance', value, display, 'note', source)
      if [actor_id, tag] == [131, '窮地スキル強化']
        item[:value_type] = 'additive_percent'
        item[:comment] = "技能：#{id_name_entries(triples.map(&:first), lookups[:skills], '技能')}"
      else
        item[:comment] = state_effect_comment(tag, triples, lookups)
      end
      [item]
    end

    def summarize_long_no_cost(actor_id, tag, body, lookups, content)
      return nil unless ['MPスキル消費なし', 'TPスキル消費なし', 'HPスキル消費なし'].include?(tag)
      ids = body.scan(/\d+/)
      return nil if ids.length < LONG_LIST_THRESHOLD
      target = LONG_TARGET_OVERRIDES[[actor_id, tag]]
      return nil unless target

      cost_type = tag[0, 2]
      jp = "#{target[0]}を使用しても#{cost_type}を消費しない"
      zh = target[1].start_with?('使用') ? "#{target[1]}不消耗#{cost_type}" : "使用#{target[1]}不消耗#{cost_type}"
      item = record(tag, jp, zh, 'fixed_cost', '0', '0', 'note', "<#{content}>")
      item[:comment] = "#{target[1]}包含：#{id_name_entries(ids, lookups[:skills], '技能')}"
      [item]
    end

    def summarize_long_type_state_addition(tag, body, lookups, content)
      supported_tags = [
        'スキルタイプステート敵付加',
        'スキルタイプステート味方付加',
        'スキルタイプステート自己付加'
      ]
      return nil unless supported_tags.include?(tag)

      triples = body.scan(/(\d+)\s*-\s*(\d+)\s*-\s*([+-]?\d+)/)
      values = triples.map { |_type_id, _state_id, value| value }
      return nil if triples.length < 2
      return summarize_mixed_type_state_addition(tag, triples, lookups, content) unless values.uniq.length == 1

      type_ids = triples.map { |type_id, _state_id, _value| type_id }.uniq
      state_ids = triples.map { |_type_id, state_id, _value| state_id }.uniq
      combinations = triples.map { |type_id, state_id, _value| [type_id, state_id] }.uniq
      complete = combinations.length == type_ids.length * state_ids.length &&
                 type_ids.product(state_ids).all? { |pair| combinations.include?(pair) }
      if !complete || combinations.length < STATE_ATTACK_SUMMARY_THRESHOLD
        return summarize_grouped_type_state_addition(tag, triples, lookups, content)
      end

      type_names = type_ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
      state_names = state_ids.map { |id| lookup(lookups[:states], id, '状态') }
      type_jp = type_names.map { |name| "「#{name}」" }.join('・')
      type_zh = type_names.map { |name| "「#{translate_name(name)}」" }.join('、')
      state_jp = state_names.join('・')
          state_zh_names = state_names.map { |name| normalize_state_name_zh(translate_name(name)) }
      state_zh = state_zh_names.join('、')
      target_jp, target_zh = {
        'スキルタイプステート敵付加' => ['敵', '对敌人'],
        'スキルタイプステート味方付加' => ['味方', '为队友'],
        'スキルタイプステート自己付加' => ['自身', '为自身']
      }.fetch(tag)
      value = values.first
      display = "#{value}%"
      if tag == 'スキルタイプステート自己付加'
        state_jp_effects = state_names.map { |name| "「#{name}」" }.join('、')
        state_zh_effects = state_zh_names.map { |name| "「#{self_state_effect_zh(name)}」" }.join('、')
        jp = "#{type_jp}使用時、自身に#{state_jp_effects}効果を#{state_ids.length == 1 ? '' : 'それぞれ'}#{display}の確率で付与"
        zh = "使用#{type_zh}时，均会以#{display}概率分别赋予自身#{state_zh_effects}效果"
      else
        jp = if state_ids.length == 1
               "#{type_jp}使用時、#{target_jp}に#{state_jp}を#{display}の確率で付与"
             else
               "#{type_jp}使用時、#{target_jp}に#{state_jp}をそれぞれ#{display}の確率で付与"
             end
        zh = if state_ids.length == 1
               "使用#{type_zh}时，均有#{display}概率#{target_zh}附加#{state_zh}"
             else
               "使用#{type_zh}时，均会以#{display}概率分别#{target_zh}附加#{state_zh}"
             end
      end
      item = record(tag, jp, zh, 'chance', value, display, 'note', "<#{content}>")
      item[:zh] = normalize_self_state_description(item[:zh]) if tag == 'スキルタイプステート自己付加'
      item[:comment] = state_effect_comment(tag, triples, lookups)
      [item]
    end

    # Mixed probabilities remain one record, with each state-to-probability mapping preserved.
    def summarize_mixed_type_state_addition(tag, triples, lookups, content)
      state_groups = []
      triples.each do |type_id, state_id, amount|
        key = [state_id, amount]
        group = state_groups.find { |entry| entry[:key] == key }
        unless group
          group = { :key => key, :type_ids => [] }
          state_groups << group
        end
        group[:type_ids] << type_id unless group[:type_ids].include?(type_id)
      end

      groups = []
      state_groups.each do |state_group|
        type_ids = state_group[:type_ids]
        group = groups.find { |entry| entry[:type_ids] == type_ids }
        unless group
          group = { :type_ids => type_ids, :effects => [] }
          groups << group
        end
        state_id, amount = state_group[:key]
        group[:effects] << { :state_id => state_id, :amount => amount }
      end

      target_jp, target_zh = {
        'スキルタイプステート敵付加' => ['敵', '对敌人'],
        'スキルタイプステート味方付加' => ['味方', '为队友'],
        'スキルタイプステート自己付加' => ['自身', '自身']
      }.fetch(tag)
      jp_clauses = []
      zh_clauses = []
      groups.each do |group|
        type_names_jp = group[:type_ids].map { |id| skill_type_lookup(lookups[:skill_types], id) }
        type_names_zh = group[:type_ids].map { |id| skill_type_effect_name_zh(lookups[:skill_types], id) }
        type_jp = type_names_jp.map { |name| "「#{name}」" }.join('・')
        type_zh = type_names_zh.map { |name| "「#{name}」" }.join('、')
        effects = group[:effects].map do |effect|
          state_name_jp = lookup(lookups[:states], effect[:state_id], '状态')
          {
            :amount => effect[:amount],
            :state_jp => state_name_jp,
            :state_zh => normalize_state_name_zh(translate_name(state_name_jp))
          }
        end
        if tag == 'スキルタイプステート自己付加'
          jp_effects = effects.map { |effect| "#{effect[:amount]}%の確率で自身に「#{effect[:state_jp]}」効果を付与" }
          zh_effects = effects.map { |effect| "以#{effect[:amount]}%概率赋予自身「#{self_state_effect_zh(effect[:state_zh])}」效果" }
        else
          jp_effects = effects.map { |effect| "#{effect[:amount]}%の確率で#{target_jp}に「#{effect[:state_jp]}」を付与" }
          zh_effects = effects.map { |effect| "以#{effect[:amount]}%概率#{target_zh}附加「#{effect[:state_zh]}」状态" }
        end
        jp_clauses << "#{type_jp}使用時、#{jp_effects.join('、')}"
        zh_clauses << "使用#{type_zh}时，#{zh_effects.join('，并')}"
      end

      value_raw = triples.map { |type_id, state_id, amount| "#{type_id}-#{state_id}-#{amount}" }.join(',')
      item = record(tag, jp_clauses.join('；'), zh_clauses.join('；'),
                    'mapping', value_raw, '', 'note', "<#{content}>")
      item[:zh] = normalize_self_state_description(item[:zh]) if tag == 'スキルタイプステート自己付加'
      item[:comment] = state_effect_comment(tag, triples.uniq, lookups)
      [item]
    end

    def summarize_grouped_type_state_addition(tag, triples, lookups, content)
      values = triples.map { |_type_id, _state_id, value| value }
      return nil unless values.uniq.length == 1

      state_entries = {}
      triples.each do |type_id, state_id, _value|
        state_entries[state_id] ||= []
        state_entries[state_id] << type_id unless state_entries[state_id].include?(type_id)
      end

      groups = []
      state_entries.each do |state_id, type_ids|
        group = groups.find { |entry| entry[:type_ids] == type_ids }
        unless group
          group = { :type_ids => type_ids, :state_ids => [] }
          groups << group
        end
        group[:state_ids] << state_id
      end

      target_jp, target_zh = {
        'スキルタイプステート敵付加' => ['敵', '对敌人'],
        'スキルタイプステート味方付加' => ['味方', '为队友'],
        'スキルタイプステート自己付加' => ['自身', '自身']
      }.fetch(tag)
      value = values.first
      display = "#{value}%"
      jp_clauses = []
      zh_clauses = []
      groups.each do |group|
        type_names_jp = group[:type_ids].map { |id| skill_type_lookup(lookups[:skill_types], id) }
        type_names_zh = type_names_jp.map { |name| translate_name(name) }
        state_names_jp = group[:state_ids].map { |id| lookup(lookups[:states], id, '状态') }
        state_names_zh = state_names_jp.map { |name| translate_name(name) }
        type_jp = type_names_jp.map { |name| "「#{name}」" }.join('・')
        type_zh = type_names_zh.map { |name| "「#{name}」" }.join('、')
        state_jp = state_names_jp.map { |name| "「#{name}」" }.join('、')
        state_zh = state_names_zh.map { |name| "「#{normalize_state_name_zh(name)}」" }.join('、')
        multiple_states = group[:state_ids].length > 1
        if tag == 'スキルタイプステート自己付加'
          jp_clauses << "#{type_jp}使用時、自身に#{state_jp}効果を#{multiple_states ? 'それぞれ' : ''}#{display}の確率で付与"
          zh_clauses << "使用#{type_zh}时，以#{display}概率#{multiple_states ? '分别' : ''}赋予自身#{state_zh}效果"
        else
          jp_clauses << if multiple_states
                          "#{type_jp}使用時、#{target_jp}に#{state_jp}をそれぞれ#{display}の確率で付与"
                        else
                          "#{type_jp}使用時、#{target_jp}に#{state_jp}を#{display}の確率で付与"
                        end
          zh_clauses << if multiple_states
                          "使用#{type_zh}时，分别以#{display}概率#{target_zh}附加#{state_zh}状态"
                        else
                          "使用#{type_zh}时，以#{display}概率#{target_zh}附加#{state_zh}状态"
                        end
        end
      end

      item = record(tag, jp_clauses.join('；'), zh_clauses.join('；'),
                    'chance', value, display, 'note', "<#{content}>")
      item[:zh] = normalize_self_state_description(item[:zh]) if tag == 'スキルタイプステート自己付加'
      item[:comment] = state_effect_comment(tag, triples.uniq, lookups)
      [item]
    end

    def summarize_long_state_attack(actor_id, tag, body, lookups, content)
      triples = body.scan(/(\d+)\s*-\s*(\d+)\s*-\s*([+-]?\d+)/)
      values = triples.map { |_target, _state, value| value }
      return nil unless values.uniq.length == 1
      return nil if triples.length < 2

      target_ids = triples.map { |target, _state, _value| target }.uniq
      state_ids = triples.map { |_target, state, _value| state }.uniq
      combinations = triples.map { |target, state, _value| [target, state] }.uniq
      complete = combinations.length == target_ids.length * state_ids.length &&
                 target_ids.product(state_ids).all? { |pair| combinations.include?(pair) }
      if tag == 'ステート特攻スキルタイプ' && (!complete || combinations.length < STATE_ATTACK_SUMMARY_THRESHOLD)
        return summarize_grouped_state_attack_type(triples, actor_id, lookups, content)
      end
      return nil if combinations.length < STATE_ATTACK_SUMMARY_THRESHOLD
      return nil unless complete

      override = LONG_TARGET_OVERRIDES[[actor_id, tag]]
      target_jp, target_zh = if override
                               override
                             else
                               long_attack_target_labels(tag, target_ids, lookups)
                             end
      state_jp, state_zh = long_state_labels(actor_id, state_ids, lookups)
      value = values.first
      display = "+#{value}%"
      jp = "#{target_jp}の#{state_jp}特攻 #{display}"
      zh = "#{target_zh}对#{state_zh}的特攻伤害 #{display}"
      item = record(tag, jp, zh, 'additive_percent', value, display, 'note', "<#{content}>")
      target_collection = tag == 'ステート特攻スキルタイプ' ? lookups[:skill_types] : lookups[:skills]
      target_label = tag == 'ステート特攻スキルタイプ' ? '技能类型' : '技能'
      item[:comment] = [
        "#{target_label}：#{id_name_entries(target_ids, target_collection, target_label)}",
        "异常状态：#{id_name_entries(state_ids, lookups[:states], '状态')}"
      ].join('；')
      [item]
    end

    def summarize_grouped_state_attack_type(triples, actor_id, lookups, content)
      values = triples.map { |_target, _state, value| value }
      return nil unless values.uniq.length == 1

      state_entries = {}
      triples.each do |target_id, state_id, _value|
        state_entries[state_id] ||= []
        state_entries[state_id] << target_id unless state_entries[state_id].include?(target_id)
      end

      groups = []
      state_entries.each do |state_id, target_ids|
        group = groups.find { |entry| entry[:target_ids] == target_ids }
        unless group
          group = { :target_ids => target_ids, :state_ids => [] }
          groups << group
        end
        group[:state_ids] << state_id
      end

      value = values.first
      effective_value = if actor_id == 239 && triples.count { |target, state, amount| target == '58' && state == '21' && amount == value } == 2
                          value.to_i * 2
                        else
                          value.to_i
                        end
      display = "+#{effective_value}%"
      jp_clauses = groups.map do |group|
        targets = group[:target_ids].map { |id| skill_type_lookup(lookups[:skill_types], id) }.join('、')
        states = group[:state_ids].map { |id| lookup(lookups[:states], id, '状态') }.join('、')
        "#{targets}の#{states}特攻 #{display}"
      end
      zh_clauses = groups.map do |group|
        targets = group[:target_ids].map { |id| translate_name(skill_type_lookup(lookups[:skill_types], id)) }.join('、')
        states = group[:state_ids].map { |id| state_name_zh(lookups, id) }.join('、')
        "#{targets}对#{states}的特攻伤害 #{display}"
      end
      item = record('ステート特攻スキルタイプ', jp_clauses.join('；'), zh_clauses.join('；'),
                    'additive_percent', effective_value.to_s, display, 'note', "<#{content}>")
      target_ids = triples.map(&:first).uniq
      state_ids = triples.map { |_target, state, _value| state }.uniq
      item[:comment] = [
        "技能类型：#{id_name_entries(target_ids, lookups[:skill_types], '技能类型')}",
        "异常状态：#{id_name_entries(state_ids, lookups[:states], '状态')}",
        state_effect_comment('スキルタイプステート敵付加', triples.uniq, lookups)
      ].join('；')
      if actor_id == 624 && triples.include?(%w[58 16 150])
        item[:comment] = [item[:comment], '固有能力说明写成白魔法、黑魔法、妖术对减速和停止特攻，但原始备注实际配置的是黑魔法（ID 23）和时魔法（ID 24）对减速、停止特攻 +150%，妖术（ID 68）仅对停止特攻 +150%；白魔法（ID 22）完全没有配置特攻效果', '植物技（ID 58）对减速特攻 +150%这一项很可能是作者将应写的68-16-150（妖术对减速特攻）误写成了58-16-150；角色本身不能使用植物技'].join('；') + '。'
      end
      if actor_id == 636 && triples.include?(%w[8 13 150])
        item[:comment] = [item[:comment], '固有能力描述写成对燃烧、冻结、电击状态的敌人使用「尖剑」可造成大量特攻伤害，但原始备注实际仅指定尖剑技、刀技、枪技对燃烧的特攻伤害 +150%，没有对冻结或电击的特攻效果。角色已通过职业获得刀技使用权限，但初始状态没有学会任何刀技技能，因此当前没有可用的刀技；角色本身不能使用枪技。因此当前只有尖剑技部分可以发挥。'].join('；')
      end
      if actor_id == 119 && triples == [['12', '15', '100'], ['42', '15', '100']]
        item[:comment] = [item[:comment], '固有能力描述写成使用「魔本术」对麻痹、电击状态的敌人可造成特攻伤害，但原始备注实际仅指定对电击的特攻伤害 +100%，没有对麻痹的特攻效果；角色本身不能使用棍技。'].join('；')
      end
      if actor_id == 239 && triples.count { |target, state, amount| target == '58' && state == '21' && amount == value } == 2
        item[:comment] = [item[:comment], '原始备注中58-21-100（植物技对消化特攻）出现两次；游戏会将两条特攻增幅相加，因此实际为+200%，对应特攻倍率为×3.0。'].join('；')
      end
      if actor_id == 864 && triples.include?(%w[69 23 150])
        item[:comment] = [item[:comment], '该「巨技对黏滑特攻 +150%」与同一角色另一条「巨技对黏滑特攻 +100%」会相加，合计特攻增幅为 +250%，对应特攻倍率为 ×3.5。'].join('；')
      end
      [item]
    end

    def summarized_target_comment(tag, target_zh, ids, lookups)
      if tag == 'パーティ特定アクター能力アップ'
        "#{target_zh}对应角色：#{id_name_entries(ids, lookups[:actors], '角色')}"
      elsif tag.include?('タイプ')
        "#{target_zh}对应技能类型：#{id_name_entries(ids, lookups[:skill_types], '技能类型')}"
      else
        "#{target_zh}包含：#{id_name_entries(ids, lookups[:skills], '技能')}"
      end
    end

    def state_effect_comment(tag, triples, lookups)
      type_entry = tag.start_with?('スキルタイプ')
      target_collection = type_entry ? lookups[:skill_types] : lookups[:skills]
      target_label = type_entry ? '技能类型' : '技能'
      pairs = triples.map do |target_id, state_id, _value|
        target = id_name_entry(target_id, target_collection, target_label)
        state = id_name_entry(state_id, lookups[:states], '状态')
        "#{target}→#{state}"
      end
      "具体对应关系：#{pairs.join('、')}"
    end

    def id_name_entries(ids, collection, fallback)
      ids.map(&:to_s).uniq.map { |id| id_name_entry(id, collection, fallback) }.join('、')
    end

    def id_name_entry(id, collection, fallback)
      return "#{id}（#{actor_name_chinese(collection, id)}）" if fallback == '角色'

      name = if fallback == '技能类型'
               skill_type_lookup(collection, id)
             elsif fallback == '技能'
               skill_lookup(collection, id)
             else
               lookup(collection, id, fallback)
             end
      name = normalize_state_name_zh(translate_name(name)) if fallback == '状态'
      return name if name.start_with?("ID #{id}") && name.include?('（无对应')

      "#{id}（#{fallback == '状态' ? name : translate_name(name)}）"
    end

    def actor_name_chinese(collection, id)
      ACTOR_NAME_TRANSLATIONS[id.to_i] || translate_name(lookup(collection, id, '角色'))
    end

    def database_name_missing?(collection, id)
      item = collection && collection[id.to_i]
      name = if item.is_a?(String)
               item
             elsif item.respond_to?(:name)
               item.name.to_s
             elsif item && item.instance_variable_defined?(:@name)
               item.instance_variable_get(:@name).to_s
             else
               item.to_s
             end
      name.empty?
    end

    def element_lookup(collection, id)
      return "ID #{id}属性（无对应属性）" if database_name_missing?(collection, id)

      lookup(collection, id, '属性')
    end

    def skill_lookup(collection, id)
      return "ID #{id}技能（无对应技能）" if database_name_missing?(collection, id)

      lookup(collection, id, '技能')
    end

    def item_lookup(collection, id)
      return "ID #{id}道具（无对应道具）" if database_name_missing?(collection, id)

      lookup(collection, id, '道具')
    end

    def malformed_repeat_type_record(body, lookups, content)
      tokens = body.split(/\s*,\s*/).reject(&:empty?)
      pairs = tokens.filter_map do |token|
        match = token.match(/\A(\d+)\s*-\s*([+-]?\d+)\z/)
        match ? [match[1], match[2]] : nil
      end
      invalid_ids = tokens.filter_map do |token|
        token.match(/\A(\d+)\z/)&.[](1)
      end
      return nil if pairs.empty? || invalid_ids.empty?

      count = pairs.first[1]
      ids = (pairs.map(&:first) + invalid_ids).uniq
      names_jp = ids.map { |id| skill_type_lookup(lookups[:skill_types], id) }
      names_zh = names_jp.map { |name| translate_name(name) }
      quoted_jp = names_jp.map { |name| "「#{name}」" }.join
      quoted_zh = names_zh.map { |name| "「#{name}」" }.join
      note = "#{quoted_jp}を#{count}次連続発動（構文エラーのため、この能力は無効）"
      description = "#{quoted_zh}连续发动#{count}次（因语法错误此能力完全不生效）"
      record('連続発動タイプ', note, description, 'invalid', body, "#{count}次（完全不生效）", 'note', "<#{content}>")
    end

    def skill_type_missing?(collection, id)
      database_name_missing?(collection, id)
    end

    def skill_type_lookup(collection, id)
      return "ID #{id}技能类型（无对应技能类型）" if skill_type_missing?(collection, id)

      lookup(collection, id, '技能类型')
    end

    def skill_type_effect_name_zh(collection, id)
      return '由装备武器提供的技能' if id.to_i == 64

      translate_name(skill_type_lookup(collection, id))
    end

    def percent_change_phrase_jp(value)
      amount = value.to_f
      return '変化なし' if amount.zero?

      amount.positive? ? "を#{number(amount)}%アップ" : "を#{number(amount.abs)}%ダウン"
    end

    def percent_change_phrase_zh(value)
      amount = value.to_f
      return '不变' if amount.zero?

      amount.positive? ? "提高#{number(amount)}%" : "降低#{number(amount.abs)}%"
    end

    def long_target_labels(actor_id, tag, pairs, lookups)
      override = LONG_TARGET_OVERRIDES[[actor_id, tag]]
      return override if override
      if tag == 'パーティ特定アクター能力アップ'
        return ['魔獣系モンスター', '兽族伙伴'] if actor_id == 60
        ids = pairs.map(&:first).uniq
        names_jp = ids.map { |id| lookup(lookups[:actors], id, '角色') }.uniq
        names_zh = ids.map { |id| actor_name_chinese(lookups[:actors], id) }.uniq
        return [names_jp.join('、'), names_zh.join('、')]
      end

      count = pairs.map(&:first).uniq.length
      if tag.include?('タイプ')
        ["指定された#{count}種類のスキル", "指定的#{count}类技能"]
      else
        ["指定された#{count}個のスキル", "指定的#{count}个技能"]
      end
    end

    def long_attack_target_labels(tag, ids, lookups)
      type_entry = tag == 'ステート特攻スキルタイプ'
      if ids.length <= 4
        names = ids.map do |id|
          type_entry ? skill_type_lookup(lookups[:skill_types], id) : skill_lookup(lookups[:skills], id)
        end
        joined = names.join('、')
        return [joined, joined]
      end
      if type_entry
        ["指定された#{ids.length}種類のスキル", "指定的#{ids.length}类技能"]
      else
        ["指定された#{ids.length}個のスキル", "指定的#{ids.length}个技能"]
      end
    end

    def long_state_labels(actor_id, ids, lookups)
      common_ids = ids.map(&:to_i).sort
      return ['全ての通常状態異常', '全部常规异常状态'] if common_ids == COMMON_STATUS_IDS
      override = STATE_SCOPE_OVERRIDES[actor_id]
      return override[1] if override && common_ids == override[0].sort
      if ids.length <= 5
        names = ids.map { |id| lookup(lookups[:states], id, '状态') }
        joined_jp = names.join('、')
        joined_zh = names.map { |name| normalize_state_name_zh(translate_name(name)) }.join('、')
        return [joined_jp, joined_zh]
      end
      ["指定された#{ids.length}種類の状態異常", "指定的#{ids.length}种异常状态"]
    end

    def record_from_raw(tag, raw)
      item = record(tag, '', '', 'raw', '', '', 'note', raw, 'untranslated', 'unclassified')
      item[:category] = 'unclassified'
      item
    end

    def record(_tag, jp, zh, value_type, value_raw, value_display, source, source_raw, translation_status = 'translated', importance = 'core')
      {
        :category => category_for_tag(_tag),
        :importance => importance,
        :jp => jp.to_s,
        :zh => translate_chinese_text(zh),
        :value_type => value_type,
        :value_raw => value_raw,
        :value_display => value_display,
        :source => source,
        :translation_status => translation_status,
        :original_text => source == 'note' ? source_raw : jp,
        :source_raw => source_raw,
        :comment => ''
      }
    end

    # Preserve duplicate records, but explain the effect of the second and later copies.
    def annotate_duplicate_records(records)
      records.each do |item|
        occurrence = item[:duplicate_occurrence].to_i
        next if occurrence < 2 || item[:importance].to_s == 'skipped'

        source_label = item[:source].to_s == 'trait' ? '特性' : '备注'
        suffix = "（#{source_label}出现第#{occurrence}次；#{duplicate_effect_rule(item)}）"
        item[:zh] = [item[:zh].to_s, suffix].reject(&:empty?).join
      end
    end

    def duplicate_effect_rule(item)
      if item[:source].to_s == 'trait'
        code = item[:source_raw].to_s[/\Acode=(\d+)/, 1].to_i
        data_id = item[:source_raw].to_s[/data_id=(\d+)/, 1].to_i
        return '效果可叠加，倍率相乘' if [11, 13, 21, 23].include?(code)
        return '多个HP再生率按“1 - ∏(1 - 各项数值)”合并' if code == 22 && data_id == 7
        return '效果可叠加，数值相加' if code == 22
        return '每条特性分别进行概率判定，重复记录会增加触发次数' if code == 61
        return '通常不叠加，仅保留一次效果' if [31, 41, 43, 51, 52, 55].include?(code)
        return '效果按游戏特性代码分别计算'
      end

      tag = item[:source_raw].to_s[/\A<([^\s:>]+)/, 1].to_s
      return '效果不可叠加，仅生效一次' if tag == '時間停止無視' || tag.start_with?('速攻発動', '頑強発動', '遅攻発動')
      return '追加发动次数会加算' if tag == '連続発動タイプ' || tag == '連続発動スキル'
      return '最终攻击属性会去重，重复记录不会增加属性' if tag == '属性追加'
      return '效果按该备注的各项参数分别计算'
    end

    def category_for_tag(tag)
      return 'skill_chain' if tag == 'スキルチェーン'
      return 'stat_change' if ['能力値置き換え', '能力値加算'].include?(tag)
      return 'attribute' if ['属性追加', '属性吸収', '属性反射', '属性貫通'].include?(tag)
      return 'trigger' if ['戦闘開始時発動', 'ターン終了時発動', 'オートステート', '反撃スキル'].include?(tag)
      return 'cost' if tag.include?('消費率') || tag.include?('消費なし') || tag == 'チェーン消費軽減'
      return 'skill_boost' if tag.include?('スキル') || tag == 'スキルタイプ強化'
      return 'resistance' if tag.include?('有効度')
      'special'
    end

    def trait_category(code)
      return 'parameter' if code == 21
      return 'skill' if [41, 43].include?(code)
      return 'equipment' if [51, 52, 55].include?(code)
      return 'attack' if [31, 32].include?(code)
      return 'resistance' if [11, 13].include?(code)
      return 'action' if code == 61
      'trait'
    end

    def trait_value_type(code)
      return 'multiplier' if [11, 13, 21, 23].include?(code)
      return 'additive_percent' if code == 22
      return 'additive' if code == 33
      return 'action_plus' if code == 61
      return 'count' if code == 34
      'boolean'
    end

    def trait_value_display(code, value)
      return "×#{percent(value.to_f * 100)}%" if [11, 13, 21, 23].include?(code)
      return "#{value.to_f >= 0 ? '+' : ''}#{percent(value.to_f * 100)}%" if code == 22
      return signed_number(value) if code == 33
      return "+#{number(value)}回" if code == 34
      return action_plus_phrase_jp(value) if code == 61
      ''
    end

    def trait_text(code, data_id, value, lookups)
      case code
      when 11
        element = element_lookup(lookups[:elements], data_id)
        value.to_f.zero? ? "#{element}属性ダメージ無効（ダメージ倍率×0%、ダメージ100%減少）" : "#{element}属性ダメージ量#{ratio_phrase_jp(value)}"
      when 13
        state = lookup(lookups[:states], data_id, '状态')
        value.to_f.zero? ? "#{state}無効（付与確率倍率×0%、付与確率100%減少）" : "#{state}付与確率#{ratio_phrase_jp(value)}"
      when 21
        "基本#{PARAM_NAMES[data_id.to_i] || "参数#{data_id}"}#{ratio_phrase_jp(value)}"
      when 22
        return hp_regeneration_text_jp(value) if data_id.to_i == 7
        return mp_regeneration_text_jp(value) if data_id.to_i == 8
        return tp_regeneration_text_jp(value) if data_id.to_i == 9

        name = XPARAM_NAMES[data_id.to_i] || "追加参数#{data_id}"
        "#{name}#{additive_phrase_jp(value)}"
      when 23
        return guard_effect_rate_text_jp(value) if data_id.to_i == 1

        name = SPARAM_NAMES[data_id.to_i] || "特殊参数#{data_id}"
        "#{name}#{ratio_phrase_jp(value)}"
      when 31
        "攻撃属性：#{element_lookup(lookups[:elements], data_id)}"
      when 32
        "攻撃時#{lookup(lookups[:states], data_id, '状态')}付与（基本付与率#{percent(value.to_f * 100)}%）"
      when 33
        "攻撃速度補正#{signed_number(value)}"
      when 34
        "攻撃回数追加+#{number(value)}回"
      when 41
        "#{skill_type_lookup(lookups[:skill_types], data_id)}使用可能"
      when 43
        "#{skill_lookup(lookups[:skills], data_id)}習得"
      when 51
        "#{lookup(lookups[:weapon_types], data_id, '武器类型')}装備可能"
      when 52
        "#{lookup(lookups[:armor_types], data_id, '防具类型')}装備可能"
      when 55
        { 1 => '二刀流', 2 => '両手盾', 3 => '三刀流' }[data_id.to_i] || "スロットタイプ#{data_id}"
      when 61
        action_plus_phrase_jp(value)
      else
        "特性 code=#{code}, data_id=#{data_id}, value=#{value}"
      end
    end

    def trait_text_zh(code, data_id, value, lookups)
      case code
      when 11
        element = translate_name(element_lookup(lookups[:elements], data_id))
        value.to_f.zero? ? "免疫#{element}属性伤害（伤害倍率×0%，伤害减少100%）" : "受到#{element}属性伤害#{ratio_phrase_zh(value)}"
      when 13
        state = state_name_zh(lookups, data_id)
        value.to_f.zero? ? "免疫#{state}状态（附加概率倍率×0%，附加概率减少100%）" : "被施加#{state}状态的概率#{ratio_phrase_zh(value)}"
      when 21
        names = { '最大HP' => '最大HP', '最大MP' => '最大MP', '攻撃力' => '攻击力', '防御力' => '防御力', '魔力' => '魔力', '精神力' => '精神力', '素早さ' => '敏捷', '器用さ' => '灵巧' }
        jp_name = PARAM_NAMES[data_id.to_i] || "参数#{data_id}"
        "基础#{names[jp_name] || jp_name}#{ratio_phrase_zh(value)}"
      when 22
        return hp_regeneration_text_zh(value) if data_id.to_i == 7
        return mp_regeneration_text_zh(value) if data_id.to_i == 8
        return tp_regeneration_text_zh(value) if data_id.to_i == 9

        "#{XPARAM_NAMES_ZH[data_id.to_i] || "追加参数#{data_id}"}#{additive_phrase_zh(value)}"
      when 23
        return guard_effect_rate_text_zh(value) if data_id.to_i == 1

        special_name = SPARAM_NAMES_ZH[data_id.to_i] || "特殊参数#{data_id}"
        "#{special_name}#{ratio_phrase_zh(value)}"
      when 31
        "普通攻击及采用普通攻击属性的技能附加#{element_lookup(lookups[:elements], data_id)}属性"
      when 32
        "攻击时附加#{state_name_zh(lookups, data_id)}（基础附加率#{percent(value.to_f * 100)}%）"
      when 33
        "攻击速度修正#{signed_number(value)}"
      when 34
        "攻击次数增加+#{number(value)}次"
      when 41
        "可以使用#{skill_type_lookup(lookups[:skill_types], data_id)}"
      when 43
        "习得#{skill_lookup(lookups[:skills], data_id)}"
      when 51
        "可以装备#{lookup(lookups[:weapon_types], data_id, '武器类型')}"
      when 52
        "可以装备#{lookup(lookups[:armor_types], data_id, '防具类型')}"
      when 55
        { 1 => '二刀流', 2 => '双手盾', 3 => '三刀流' }[data_id.to_i] || "装备槽类型#{data_id}"
      when 61
        action_plus_phrase_zh(value)
      else
        ''
      end
    end

    def trait_comment(code, data_id, value, actor_id = nil)
      if actor_id.to_i == 854 && code.to_i == 11 && data_id.to_i == 50 && value.to_f == 0.25
        return '属性ID 50是终焉属性，不是修罗属性（ID 51）。该特性使受到的终焉属性伤害变为25%（减少75%）；角色自身特性和备注中未找到修罗属性抗性。'
      end
      if actor_id.to_i == 724 && code.to_i == 41 && data_id.to_i == 45
        return '固有能力描述写成可以使用「忍术」「暗技」，但原始特性将 data_id=31（忍术）误写成了 data_id=45（医术），所以当前记录显示为可以使用「医术」；角色本身不能使用忍术，但初始职业「忍神」（ID 7030）可以让角色使用忍术。'
      end
      if actor_id.to_i == 507 && code.to_i == 22 && data_id.to_i == 1 && value.to_f == 0.15
        return '固有能力描述写成会心率和会心伤害大幅提升，但该特性code=22、data_id=1、value=0.15实际使物理闪避率增加15%；会心率对应的data_id应为2，因此很可能是作者误将2写成了1。角色另有<会心ダメージ増加:50>，会心伤害增加50%的部分可以正常生效；不符的是会心率提升部分。'
      end
      if actor_id.to_i == 617 && code.to_i == 21 && data_id.to_i == 6 && value.to_f == 0.3
        return '固有能力说明写成「敏捷提升30%」，但该特性实际将基础敏捷乘以0.3，即变为原值的30%（降低70%），并非提升30%。最终敏捷仍受其他倍率和强化影响，且游戏计算下限为1；这里的30%不是敏捷下限。'
      end
      if actor_id.to_i == 4 && code.to_i == 21 && data_id.to_i == 0 && [10.0, 6.0].include?(value.to_f)
        return '角色同时拥有最大HP×1000%与×600%两项倍率；游戏按乘法合并，最终最大HP为基础值的60倍，即×6000%。'
      end
      if actor_id.to_i == 4 && code.to_i == 21 && data_id.to_i == 1 && [10.0, 5.0].include?(value.to_f)
        return '角色同时拥有最大MP×1000%与×500%两项倍率；游戏按乘法合并，最终最大MP为基础值的50倍，即×5000%。'
      end
      if actor_id.to_i == 658 && code.to_i == 21 && data_id.to_i == 6 && value.to_f == 1.5
        return '角色同时拥有两项基础敏捷×150%倍率；游戏按乘法合并，最终基础敏捷倍率为×225%。'
      end
      if actor_id.to_i == 998 && code.to_i == 21 && data_id.to_i == 2 && value.to_f == 10.0
        return '角色同时拥有两项基础攻击力×1000%倍率；游戏按乘法合并，最终基础攻击力倍率为×10000%，即基础攻击力的100倍。'
      end
      if code.to_i == 22 && data_id.to_i == 7
        return '游戏将多个HP再生率按“1 - ∏(1 - 各项数值)”合并；最终每回合HP变化量为最大HP×最终HP再生率，正值恢复HP，负值造成伤害。'
      end

      return '' unless code.to_i == 23 && data_id.to_i == 1

      raw_rate = value.to_f
      effective_rate = [1.0, raw_rate].max
      base_damage_rate = 100.0 / (2.0 * effective_rate)
      effect = if raw_rate < 1.0
                 '该参数低于下限，因此不会改变最终防御减伤。'
               else
                 "最终防御效果率为×#{percent(effective_rate * 100)}%，防御时受到未防御伤害的#{percent(base_damage_rate)}%。"
               end
      "游戏取防御效果率特性的最大值，并以×100%为下限；防御伤害按“伤害÷（2×最终防御效果率）”计算。#{effect}"
    end

    def hp_regeneration_text_jp(value)
      amount = value.to_f * 100
      return '毎ターンのHP増減なし' if amount.zero?

      amount > 0 ? "毎ターン最大HPの#{percent(amount)}%回復" : "毎ターン最大HPの#{percent(amount.abs)}%ダメージ"
    end

    def hp_regeneration_text_zh(value)
      amount = value.to_f * 100
      return '每回合HP不发生变化' if amount.zero?

      amount > 0 ? "每回合恢复最大HP的#{percent(amount)}%" : "每回合受到最大HP的#{percent(amount.abs)}%伤害"
    end

    def mp_regeneration_text_jp(value)
      amount = value.to_f * 100
      return '毎ターン終了時、MPの自動回復なし' if amount.zero?

      amount > 0 ? "毎ターン終了時、最大MPの#{percent(amount)}%を自動回復" : "毎ターン終了時、最大MPの#{percent(amount.abs)}%を失う"
    end

    def mp_regeneration_text_zh(value)
      amount = value.to_f * 100
      return '每回合结束时不自动恢复MP' if amount.zero?

      amount > 0 ? "每回合结束时自动恢复最大MP的#{percent(amount)}%" : "每回合结束时失去最大MP的#{percent(amount.abs)}%"
    end

    def tp_regeneration_text_jp(value)
      amount = value.to_f * 100
      return '毎ターン終了時、SP（TP）の自動回復なし' if amount.zero?

      amount > 0 ? "毎ターン終了時、最大SPの#{percent(amount)}%（切り上げ）を自動回復" : "毎ターン終了時、最大SPの#{percent(amount.abs)}%（切り上げ）を失う"
    end

    def tp_regeneration_text_zh(value)
      amount = value.to_f * 100
      return '每回合结束时不自动恢复SP（TP）' if amount.zero?

      amount > 0 ? "每回合结束时自动恢复最大SP的#{percent(amount)}%（向上取整）" : "每回合结束时失去最大SP的#{percent(amount.abs)}%（向上取整）"
    end

    def guard_effect_rate_text_jp(value)
      raw_rate = value.to_f
      raw_percent = percent(raw_rate * 100)
      effective_rate = [1.0, raw_rate].max
      damage_percent = percent(100.0 / (2.0 * effective_rate))
      if raw_rate < 1.0
        "防御効果率パラメータ×#{raw_percent}%（この効果は発動しない）"
      else
        "防御効果率パラメータ×#{raw_percent}%（防御時のダメージは非防御時の#{damage_percent}%）"
      end
    end

    def guard_effect_rate_text_zh(value)
      raw_rate = value.to_f
      raw_percent = percent(raw_rate * 100)
      effective_rate = [1.0, raw_rate].max
      effective_percent = percent(effective_rate * 100)
      damage_percent = percent(100.0 / (2.0 * effective_rate))
      if raw_rate < 1.0
        "防御效果率参数为#{raw_percent}%（受下限限制，实际按#{effective_percent}%计算；该效果实际上无效）"
      else
        "防御效果率参数为×#{raw_percent}%（防御时受到未防御伤害的#{damage_percent}%）"
      end
    end

    # Action Plus values use the integer part for guaranteed extra actions and
    # the fractional part as the probability of one more extra action.
    def action_plus_parts(value)
      amount = value.to_f
      guaranteed = amount.floor
      chance = (amount - guaranteed).round(6)
      [guaranteed, chance]
    end

    def action_plus_phrase_jp(value)
      guaranteed, chance = action_plus_parts(value)
      parts = []
      if guaranteed > 0
        parts << "必ず追加行動#{guaranteed}回（合計#{guaranteed + 1}回行動）"
      end
      if chance > 0
        prefix = guaranteed > 0 ? '、さらに' : ''
        parts << "#{prefix}#{percent(chance * 100)}%の確率で追加行動1回"
      end
      parts.empty? ? '追加行動なし' : parts.join
    end

    def action_plus_phrase_zh(value)
      guaranteed, chance = action_plus_parts(value)
      parts = []
      if guaranteed > 0
        parts << "必定追加#{guaranteed}次行动（共#{guaranteed + 1}次行动）"
      end
      if chance > 0
        prefix = guaranteed > 0 ? '，另有' : ''
        parts << "#{prefix}#{percent(chance * 100)}%概率追加1次行动"
      end
      parts.empty? ? '无追加行动' : parts.join
    end

    def numeric_value_type(tag)
      return 'multiplier' if ['TPタイプ消費率', 'TP消費率', 'HP消費率', 'MP消費率', 'ゴールド消費率', '物理ダメージ率', '魔法ダメージ率', '属性有効度', '拡張属性有効度', 'ステート有効度', '拡張ステート有効度', '弱体有効度', '拡張弱体有効度'].include?(tag)
      return 'additive_percent' if ['スキルタイプ強化', '属性強化', '武器強化物理', '武器強化魔法', '武器強化必中', 'スキル強化', 'ステート割合強化スキル', '開始時TP', 'ダメージアップ', '単発スキルダメージアップ'].include?(tag)
      'raw'
    end

    def extract_numeric_value(tag, body, index)
      if ['スキルタイプ強化', '属性強化', '武器強化物理', '武器強化魔法', '武器強化必中', 'スキル強化', 'ステート割合強化スキル', '属性有効度', '拡張属性有効度', 'ステート有効度', '拡張ステート有効度', '弱体有効度', '拡張弱体有効度'].include?(tag)
        pair = body.scan(/(\d+)-([+-]?\d+)/)[index]
        return pair ? pair[1] : ''
      end
      match = body.match(/([+-]?\d+)%?/) 
      match ? match[1] : ''
    end

    def numeric_value_display(tag, raw)
      return '' if raw.to_s.empty?
      number = raw.to_i
      return multiplier_display(number) if numeric_value_type(tag) == 'multiplier'
      "+#{number}%"
    end

    def multiplier_display(value)
      number = value.to_i
      delta = number - 100
      "×#{number}%（#{delta >= 0 ? '+' : ''}#{delta}%）"
    end

    # Keep the multiplier and explicitly state whether the affected quantity rises or falls.
    def ratio_phrase_zh(value)
      rate = value.to_f * 100
      delta = rate - 100
      change = if delta > 0
                 "增加#{percent(delta)}%"
               elsif delta < 0
                 "减少#{percent(delta.abs)}%"
               else
                 '不变'
               end
      "变为×#{percent(rate)}%（#{change}）"
    end

    def ratio_phrase_jp(value)
      rate = value.to_f * 100
      delta = rate - 100
      change = if delta > 0
                 "#{percent(delta)}%増加"
               elsif delta < 0
                 "#{percent(delta.abs)}%減少"
               else
                 '変化なし'
               end
      "が×#{percent(rate)}%（#{change}）"
    end

    # Note values store the multiplier as a percentage number (for example 50 or 150).
    def percent_ratio_phrase_zh(value)
      ratio_phrase_zh(value.to_f / 100.0)
    end

    def percent_ratio_phrase_jp(value)
      ratio_phrase_jp(value.to_f / 100.0)
    end

    def fixed_ratio_phrase_zh(value)
      rate = value.to_f
      delta = rate - 100
      change = if delta > 0
                 "伤害增加#{percent(delta)}%"
               elsif delta < 0
                 "伤害减少#{percent(delta.abs)}%"
               else
                 '伤害不变'
               end
      "×#{percent(rate)}%（#{change}）"
    end

    def fixed_ratio_phrase_jp(value)
      rate = value.to_f
      delta = rate - 100
      change = if delta > 0
                 "ダメージ#{percent(delta)}%増加"
               elsif delta < 0
                 "ダメージ#{percent(delta.abs)}%減少"
               else
                 'ダメージ変化なし'
               end
      "×#{percent(rate)}%（#{change}）"
    end

    def additive_phrase_zh(value)
      amount = value.to_f * 100
      return '不变' if amount.zero?
      amount > 0 ? "增加#{percent(amount)}%" : "减少#{percent(amount.abs)}%"
    end

    def additive_phrase_jp(value)
      amount = value.to_f * 100
      return '変化なし' if amount.zero?
      amount > 0 ? "#{percent(amount)}%増加" : "#{percent(amount.abs)}%減少"
    end

    def lookup(collection, id, fallback)
      item = collection && collection[id.to_i]
      name = if item.is_a?(String)
               item
             elsif item.respond_to?(:name)
               item.name.to_s
             elsif item && item.instance_variable_defined?(:@name)
               item.instance_variable_get(:@name).to_s
             else
               item.to_s
             end
      name.empty? ? "#{fallback}#{id}" : name
    end

    def percent(value)
      value.round(4).to_s.sub(/\.0+\z/, '')
    end

    def number(value)
      value.to_f.round(4).to_s.sub(/\.0+\z/, '')
    end

    def signed_number(value)
      n = number(value)
      value.to_f >= 0 ? "+#{n}" : n
    end

    def write_csv(filename, rows)
      text = CSV.generate(:row_sep => "\r\n", :force_quotes => true) { |csv| rows.each { |row| csv << row } }
      path = File.join(@output_dir, filename)
      File.binwrite(path, "\xEF\xBB\xBF".b + text.encode('UTF-8').b)
    end

    # The game calls this resource SP; TP is retained only in raw source tags.
    def display_text(value)
      text = value.to_s
      protected_tags = []
      text = text.gsub(/<[^>]*>/) do |tag|
        protected_tags << tag
        "\u0000#{protected_tags.length - 1}\u0000"
      end
      text = text.gsub('TP', 'SP')
      text.gsub(/\u0000(\d+)\u0000/) { protected_tags[Regexp.last_match(1).to_i] }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  root = ARGV[0] || File.expand_path('..', __dir__)
  output_dir = ARGV[1] || GouqiActorAbilityReintroducer::OUTPUT_DIR
  GouqiActorAbilityReintroducer.run(root, output_dir)
end
