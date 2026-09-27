class_name GameLessons
extends RefCounted

## 教学课程内容（面向中小学生：句子更短、用词更简单、配色在浅色面板上清晰可读）。
## setup_mode：
##   "none"    不改动魔方
##   "random"  随机打乱（setup 为步数）
##   "inverse" 先做好 setup 公式的“逆”，也就是摆出该公式能解决的图案
##   "moves"   直接执行 setup 里的操作
## demo：点“演示”时播放的操作（通常就是本课要教的公式）

static func all() -> Array:
	return [
		{
			"title": "第 1 课 · 认识二阶魔方",
			"body": """[b][color=#b45309]二阶魔方又叫“口袋魔方”。[/color][/b]
它一共只有 [b]8 个小方块[/b]，每个小方块有 3 张彩色贴纸。

[b]我们的目标[/b]
让每一个面的颜色都变成一样的！

[b]怎么玩[/b]
· [color=#1d4ed8]按住魔方拖动[/color] → 转动那一层
· [color=#1d4ed8]在空白处拖动[/color] → 转动视角，看看魔方的后面
· [color=#1d4ed8]滚轮[/color] → 把魔方放大或缩小
· 键盘 [code]U D L R F B[/code] → 转动对应的面
· [code]空格[/code] 打乱 · [code]Z[/code] 撤销 · [code]H[/code] 提示 · [code]S[/code] 自动复原

[b]颜色[/b]
上面黄色、下面白色、前面绿色、后面蓝色、右面红色、左面橙色。
左边的小图是“展开图”，它会一直告诉你魔方现在的样子。""",
			"setup_mode": "none",
			"setup": "",
			"demo": "",
			"coach": false,
		},
		{
			"title": "第 2 课 · 认识公式记号",
			"body": """[b][color=#b45309]公式就像“动作口令”。[/color][/b]
· [code]R[/code] = 右面顺时针转 90°
· [code]U[/code] = 上面顺时针转 90°
· [code]F[/code] = 前面顺时针转 90°
· 加一个小撇 [code]'[/code] = 反过来转，例如 [code]R'[/code]
· 加一个 [code]2[/code] = 转两下（180°），例如 [code]U2[/code]

[b]热身小公式：[/b][color=#1d4ed8][code]R U R' U'[/code][/color]
它是很多公式的“小积木”。连着做 6 次，魔方会变回原样，很神奇！

先点 [b]▶ 走一步[/b] 慢慢跟着做，再点 [b]🎬 演示[/b] 看完整效果。
做错了也没关系，点 [b]↩ 撤销[/b] 就能回去。""",
			"setup_mode": "none",
			"setup": "",
			"demo": "R U R' U'",
			"coach": false,
		},
		{
			"title": "第 3 课 · 第一步：白色一层",
			"body": """[b][color=#b45309]先把白色这一层做好。[/color][/b]
把 4 张白色贴纸都转到 [b]下面[/b]，而且每个侧面颜色要两两对齐。

[b]小窍门[/b]
1. 先找一块白色，把它转到该去的位置，让白色朝下。
2. 再做第二块、第三块…… 注意不要弄乱已经做好的。
3. 白色块在上面时，把它转到目标位置的[b]正上方[/b]，
   然后反复做 [code]R U R' U'[/code] 把它“送”下去。

[b]来试试[/b]
点 [b]💡 提示[/b] 让电脑告诉你现在有几块做好了、下一步怎么转；
点 [b]▶ 走一步[/b] 可以一步一步跟着学。""",
			"setup_mode": "random",
			"setup": "12",
			"demo": "",
			"coach": true,
		},
		{
			"title": "第 4 课 · 第二步：黄色面（OLL）",
			"body": """[b][color=#b45309]把黄色都翻到上面来。[/color][/b]
白色一层做好以后，我们把 4 张黄色贴纸都翻到 [b]顶面[/b]。
这一步只看颜色朝向，先不管位置对不对。

[b]常见样子和公式[/b]
· [color=#1d4ed8]小鱼[/color]：[code]R U R' U R U2 R'[/code]
· [color=#1d4ed8]反小鱼[/color]：[code]R U2 R' U' R U' R'[/code]
· [color=#1d4ed8]H 形[/color]：[code]R U R' U R U' R' U R U2 R'[/code]
· [color=#1d4ed8]Π 形[/color]：[code]R U2 R2 U' R2 U' R2 U2 R[/code]
· [color=#1d4ed8]T 形[/color]：[code]R U R' U' R' F R F'[/code]
· [color=#1d4ed8]L 形[/color]：[code]F R' F' R U R U' R'[/code]

[b]怎么做[/b]
先转 [b]顶面[/b]，让黄色图案和上面某个样子一样，再做那个公式。
不想自己找？点 [b]💡 提示[/b]，电脑会帮你认出来！""",
			"setup_mode": "inverse",
			"setup": "R U R' U R U2 R'",
			"demo": "R U R' U R U2 R'",
			"coach": true,
		},
		{
			"title": "第 5 课 · 第三步：角块回家（PLL）",
			"body": """[b][color=#b45309]最后一步：让角块回到自己的家。[/color][/b]
顶面已经全黄了，但有的角块站错了位置。把它们换回来，魔方就复原啦！

[b]只有两种情况[/b]
· [color=#1d4ed8]相邻两块要交换[/color]
  [code]R U R' U' R' F R2 U' R' U' R U R' F'[/code]
· [color=#1d4ed8]对角两块要交换[/color]
  [code]F R U' R' U' R U R' F' R U R' U' R' F R F'[/code]

[b]找线索[/b]
先看看有没有哪个角块已经站对了（颜色朝向不对也没关系）。
找到一个“站对”的角块当参照，就知道另外两块该怎么换。
点 [b]💡 提示[/b] 直接看答案也可以哦。""",
			"setup_mode": "inverse",
			"setup": "R U R' U' R' F R2 U' R' U' R U R' F'",
			"demo": "R U R' U' R' F R2 U' R' U' R U R' F'",
			"coach": true,
		},
		{
			"title": "第 6 课 · 完整复原一遍",
			"body": """[b][color=#b45309]把三步连起来！[/color][/b]
① 白色一层 → ② 黄色面 → ③ 角块回家

点 [b]🎲 打乱[/b] 弄一个随机的魔方，然后：
· [b]💡 提示[/b]：看看现在该做哪一步、用什么公式
· [b]▶ 走一步[/b]：让电脑带你走一小步
· [b]🎬 帮我做完这一步[/b]：把当前这一阶段做完
· [b]🤖 自动复原[/b]：看电脑一次做完（旁边会显示每一步在做什么）

自己做的时候随时可以 [b]↩ 撤销[/b]，不要害怕出错。""",
			"setup_mode": "random",
			"setup": "12",
			"demo": "",
			"coach": true,
		},
		{
			"title": "第 7 课 · 计时挑战",
			"body": """[b][color=#b45309]来比一比，看看你有多快！[/color][/b]
1. 点 [b]🎲 打乱[/b]（或者按空格）。
2. 你开始转第一步时，计时器会自动开始。
3. 复原后计时自动停下，还会显示用时和步数。

[b]小目标[/b]
· 1 分钟以内：已经学会啦！
· 30 秒以内：非常熟练！
· 15 秒以内：太厉害了！

想变快，就多练“白色一层”，看清楚再动手，少走弯路。
你的最好成绩会一直记在这里，加油！""",
			"setup_mode": "random",
			"setup": "12",
			"demo": "",
			"coach": true,
		},
	]
