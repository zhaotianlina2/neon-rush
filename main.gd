extends Node3D
## NEON RUSH 霓虹狂飙 —— 3D 无尽狂飙，全部场景代码化构建
## 操作：A/D 或 ←/→ 变道，Space/W/↑ 跳跃，R 重开

# ---------------- 常量 ----------------
const LANE_X := [-2.7, 0.0, 2.7]
const SEG_LEN := 24.0
const SEG_COUNT := 9
const ROAD_W := 8.8
const BASE_SPEED := 17.0
const MAX_SPEED := 54.0
const GRAVITY := 46.0
const JUMP_V := 14.5
const HOVER_Y := 1.05
const SPAWN_Z := -95.0

const C_MAGENTA := Color(1.0, 0.16, 0.84)
const C_CYAN := Color(0.05, 0.92, 1.0)
const C_RED := Color(1.0, 0.22, 0.28)
const C_ORANGE := Color(1.0, 0.55, 0.1)
const C_PURPLE := Color(0.62, 0.3, 1.0)

# ---------------- 状态 ----------------
var state := "menu"            # menu | run | dead
var speed := 0.0
var dist := 0.0
var score := 0
var orbs := 0
var best := 0
var lane := 1
var lane_from := 1
var lane_t := 1.0
var player_y := HOVER_Y
var jump_v := 0.0
var on_ground := true
var shake := 0.0
var dead_timer := 0.0
var since_spawn := 0.0
var menu_t := 0.0

# 节点
var cam: Camera3D
var player: Node3D
var player_model: Node3D
var sun: DirectionalLight3D
var road_root: Node3D
var seg_nodes: Array = []
var buildings: Array = []
var streaks: Array = []
var obstacle_pool: Array = []   # 已回收可用
var obstacles_active: Array = []
var orb_pool: Array = []
var orbs_active: Array = []
var ui: CanvasLayer
var lbl_score: Label
var lbl_best: Label
var lbl_speed: Label
var lbl_orbs: Label
var menu_ui: Control
var dead_ui: Control
var dead_score: Label
var dead_best: Label
var new_badge: Label
var hud_font: SystemFont

# 音频
var snd_pickup: AudioStreamPlayer
var snd_jump: AudioStreamPlayer
var snd_lane: AudioStreamPlayer
var snd_crash: AudioStreamPlayer

# 截图 QA
var qa_dir := ""
var qa_times := [0.6, 3.2, 5.6, 7.8]
var qa_i := 0
var qa_t := 0.0
var qa_started := false

# ---------------- 构建 ----------------
func _ready() -> void:
	randomize()
	hud_font = SystemFont.new()
	hud_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei"])
	_build_environment()
	_build_player()
	_build_road()
	_build_buildings()
	_build_streaks()
	_build_ui()
	_build_audio()
	_load_best()
	_parse_args()

# ---------------- 环境 ----------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.016, 0.004, 0.055)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.14, 0.08, 0.28)
	e.ambient_light_energy = 1.6
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.15
	e.glow_enabled = true
	e.glow_intensity = 1.25
	e.glow_strength = 1.02
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.02, 0.13)
	e.fog_density = 0.0075
	we.environment = e
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 24, 0)
	sun.light_color = Color(0.55, 0.6, 1.0)
	sun.light_energy = 0.35
	add_child(sun)

	# 大地平面（路面微抬升，城市有地面）
	var ground := _mesh(MeshInstance3D.new(), PlaneMesh.new(), _mat(Color(0.018, 0.013, 0.04), 0.8, 0.5))
	ground.mesh.size = Vector2(500, 700)
	ground.position = Vector3(0, -0.35, -250)
	add_child(ground)

	cam = Camera3D.new()
	cam.position = Vector3(0, 4.3, 7.6)
	cam.rotation_degrees.x = -8.0
	cam.fov = 74
	cam.current = true
	add_child(cam)

	# 合成波落日（远地平线，不受雾影响）
	var sun_outer := _mesh(MeshInstance3D.new(), SphereMesh.new(), _mat_emissive(Color(1.0, 0.25, 0.55), 2.6, true))
	sun_outer.mesh.radius = 34.0
	sun_outer.mesh.height = 68.0
	sun_outer.mesh.material.fog_disabled = true
	sun_outer.mesh.material.albedo_color.a = 0.5
	sun_outer.position = Vector3(0, 6, -420)
	sun_outer.scale = Vector3(1, 1, 0.02)
	add_child(sun_outer)
	var sun_inner := _mesh(MeshInstance3D.new(), SphereMesh.new(), _mat_emissive(Color(1.0, 0.62, 0.2), 3.6, true))
	sun_inner.mesh.radius = 27.0
	sun_inner.mesh.height = 54.0
	sun_inner.mesh.material.fog_disabled = true
	sun_inner.mesh.material.albedo_color.a = 0.8
	sun_inner.position = Vector3(0, 6, -419)
	sun_inner.scale = Vector3(1, 1, 0.02)
	add_child(sun_inner)

# ---------------- 玩家 ----------------
func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	player_model = Node3D.new()
	player.add_child(player_model)
	if ResourceLoader.exists("res://assets/player.glb"):
		var packed: PackedScene = load("res://assets/player.glb")
		player_model.add_child(packed.instantiate())
	else:
		_build_fallback_ship(player_model)

var ship_engine_mats: Array = []
var ship_underglow: MeshInstance3D

func _build_fallback_ship(root: Node3D) -> void:
	var hull_mat := _mat(Color(0.14, 0.09, 0.32), 0.9, 0.22)
	var trim_mat := _mat_emissive(C_MAGENTA, 4.6)
	var eng_mat := _mat_emissive(C_CYAN, 6.0)
	ship_engine_mats.append(eng_mat)

	# 主船体：两段拼出箭形
	var hull := _mesh(MeshInstance3D.new(), BoxMesh.new(), hull_mat)
	hull.mesh.size = Vector3(0.9, 0.34, 1.9)
	root.add_child(hull)
	var nose := _mesh(MeshInstance3D.new(), BoxMesh.new(), hull_mat)
	nose.mesh.size = Vector3(0.44, 0.24, 0.95)
	nose.position = Vector3(0, -0.02, -1.28)
	nose.rotation_degrees.y = 45
	root.add_child(nose)
	var tip := _mesh(MeshInstance3D.new(), BoxMesh.new(), trim_mat)
	tip.mesh.size = Vector3(0.12, 0.1, 0.5)
	tip.position = Vector3(0, -0.04, -1.62)
	tip.rotation_degrees.y = 45
	root.add_child(tip)

	# 驾驶舱
	var canopy := _mesh(MeshInstance3D.new(), SphereMesh.new(), _mat(Color(0.85, 0.95, 1.0, 0.4), 0.2, 0.05))
	canopy.mesh.radius = 0.28
	canopy.mesh.height = 0.44
	canopy.position = Vector3(0, 0.2, -0.25)
	canopy.scale = Vector3(0.9, 0.7, 1.5)
	root.add_child(canopy)

	# 侧翼 + 翼灯
	for side in [-1, 1]:
		var wing := _mesh(MeshInstance3D.new(), BoxMesh.new(), hull_mat)
		wing.mesh.size = Vector3(0.95, 0.07, 0.85)
		wing.position = Vector3(side * 0.86, 0.0, 0.45)
		wing.rotation_degrees.z = side * 7
		wing.rotation_degrees.y = side * 8
		root.add_child(wing)
		var strip := _mesh(MeshInstance3D.new(), BoxMesh.new(), trim_mat)
		strip.mesh.size = Vector3(0.9, 0.04, 0.07)
		strip.position = Vector3(side * 1.14, 0.02, 0.3)
		strip.rotation_degrees.y = side * 8
		root.add_child(strip)
		var engine := _mesh(MeshInstance3D.new(), CylinderMesh.new(), eng_mat)
		engine.mesh.top_radius = 0.13
		engine.mesh.bottom_radius = 0.19
		engine.mesh.height = 0.42
		engine.rotation_degrees.x = 90
		engine.position = Vector3(side * 0.42, 0.0, 1.02)
		root.add_child(engine)
		# 喷焰：半透明锥体
		var flame := _mesh(MeshInstance3D.new(), CylinderMesh.new(), _mat_emissive(Color(0.5, 0.95, 1.0), 3.0, true))
		flame.mesh.top_radius = 0.16
		flame.mesh.bottom_radius = 0.02
		flame.mesh.height = 1.1
		flame.rotation_degrees.x = -90
		flame.position = Vector3(side * 0.42, 0.0, 1.7)
		root.add_child(flame)
		ship_engine_mats.append(flame.mesh.material)

	# 背鳍
	var fin := _mesh(MeshInstance3D.new(), BoxMesh.new(), trim_mat)
	fin.mesh.size = Vector3(0.06, 0.4, 0.6)
	fin.position = Vector3(0, 0.28, 0.75)
	root.add_child(fin)

	# 底盘光晕（悬浮灯，低调）
	ship_underglow = _mesh(MeshInstance3D.new(), PlaneMesh.new(), _mat_emissive(C_CYAN, 1.4, true))
	ship_underglow.mesh.size = Vector2(1.7, 2.3)
	ship_underglow.mesh.material.albedo_color.a = 0.22
	ship_underglow.position.y = -0.55
	root.add_child(ship_underglow)
	player_model.scale = Vector3.ONE * 1.18

# ---------------- 道路 ----------------
func _build_road() -> void:
	road_root = Node3D.new()
	add_child(road_root)
	for i in range(SEG_COUNT):
		var seg := Node3D.new()
		seg.position.z = -i * SEG_LEN
		road_root.add_child(seg)
		seg_nodes.append(seg)

		var floor_mesh := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat(Color(0.045, 0.03, 0.1), 0.7, 0.35))
		floor_mesh.mesh.size = Vector3(ROAD_W + 1.2, 0.3, SEG_LEN)
		floor_mesh.position.y = -0.15
		seg.add_child(floor_mesh)

		# 两侧霓虹护栏
		for side in [-1, 1]:
			var rail := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(C_MAGENTA if i % 2 == 0 else C_CYAN, 4.2))
			rail.mesh.size = Vector3(0.14, 0.18, SEG_LEN)
			rail.position = Vector3(side * (ROAD_W / 2 + 0.1), 0.1, 0)
			seg.add_child(rail)

		# 车道虚线（两条分界线）
		for lx in [-1, 1]:
			for d in range(3):
				var dash := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(Color(0.35, 0.75, 1.0), 2.2))
				dash.mesh.size = Vector3(0.06, 0.02, 2.6)
				dash.position = Vector3(lx * ROAD_W / 6, 0.02, -SEG_LEN / 2 + d * SEG_LEN / 3 + 2)
				seg.add_child(dash)

		# 横向光带
		var band := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(C_PURPLE, 2.6))
		band.mesh.size = Vector3(ROAD_W + 1.0, 0.04, 0.3)
		band.position = Vector3(0, 0.02, -SEG_LEN / 2)
		seg.add_child(band)

		# 拱门（每 3 段一个）：环面立起、洞口朝路的方向；靠近相机时隐藏避免糊屏
		if i % 3 == 0:
			var arch := _mesh(MeshInstance3D.new(), TorusMesh.new(), _mat_emissive(C_CYAN if i % 6 == 0 else C_MAGENTA, 3.4))
			arch.mesh.inner_radius = 5.6
			arch.mesh.outer_radius = 6.1
			arch.rotation_degrees = Vector3(90, 0, 0)
			arch.position = Vector3(0, 0.2, 0)
			seg.add_child(arch)
			seg.set_meta("arch", arch)

		# 路灯柱
		for side in [-1, 1]:
			var pole := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat(Color(0.06, 0.04, 0.12), 0.8, 0.3))
			pole.mesh.size = Vector3(0.22, 5.0, 0.22)
			pole.position = Vector3(side * (ROAD_W / 2 + 1.4), 2.5, 0)
			seg.add_child(pole)
			var lamp := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(Color(0.55, 0.85, 1.0), 5.0))
			lamp.mesh.size = Vector3(0.3, 0.12, 0.3)
			lamp.position = Vector3(side * (ROAD_W / 2 + 1.4), 5.0, 0)
			seg.add_child(lamp)

# ---------------- 远景城市 ----------------
func _build_buildings() -> void:
	for i in range(24):
		var b := Node3D.new()
		var h := randf_range(5, 18)
		var body := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat(Color(0.035, 0.028, 0.075), 0.9, 0.4))
		body.mesh.size = Vector3(randf_range(3, 7), h, randf_range(3, 7))
		body.position.y = h / 2
		b.add_child(body)
		var top := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive([C_MAGENTA, C_CYAN, C_PURPLE][i % 3], 3.0))
		top.mesh.size = Vector3(body.mesh.size.x * 0.9, 0.15, body.mesh.size.z * 0.9)
		top.position.y = h + 0.05
		b.add_child(top)
		var side := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(Color(1.0, 0.75, 0.25), 1.8))
		side.mesh.size = Vector3(0.1, h * 0.6, 0.1)
		side.position = Vector3(body.mesh.size.x / 2 * (1 if i % 2 == 0 else -1), h * 0.45, 0)
		b.add_child(side)
		b.position = Vector3((20 + randf_range(0, 26)) * (1 if i % 2 == 0 else -1), 0, -randf_range(0, 240))
		add_child(b)
		buildings.append(b)

# ---------------- 速度光痕 ----------------
func _build_streaks() -> void:
	for i in range(16):
		var s := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(Color(0.6, 0.9, 1.0), 2.0, true))
		s.mesh.size = Vector3(0.05, 0.05, randf_range(2.5, 5.0))
		s.position = Vector3(randf_range(5.5, 11.0) * (1 if i % 2 == 0 else -1), randf_range(0.5, 2.8), randf_range(-90, 0))
		add_child(s)
		streaks.append(s)

# ---------------- UI ----------------
func _mk_label(parent: Node, text: String, size: int, color: Color, pos: PackedVector2Array, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", hud_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	l.position = pos[0]
	l.custom_minimum_size = pos[1] - pos[0]
	l.horizontal_alignment = align
	return l

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	lbl_score = _mk_label(ui, "0", 52, Color(1, 1, 1), PackedVector2Array([Vector2(24, 18), Vector2(500, 90)]))
	lbl_best = _mk_label(ui, "最高 0", 22, Color(0.65, 0.85, 1.0), PackedVector2Array([Vector2(26, 76), Vector2(400, 34)]))
	lbl_speed = _mk_label(ui, "", 24, C_CYAN, PackedVector2Array([Vector2(24, 660), Vector2(400, 36)]))
	lbl_orbs = _mk_label(ui, "", 24, C_MAGENTA, PackedVector2Array([Vector2(1000, 24), Vector2(260, 36)]))
	lbl_orbs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 主菜单
	menu_ui = Control.new()
	menu_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_ui)
	var title := _mk_label(menu_ui, "NEON RUSH", 92, Color(1, 1, 1), PackedVector2Array([Vector2(0, 130), Vector2(1280, 120)]))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var sub := _mk_label(menu_ui, "霓 虹 狂 飙", 40, C_CYAN, PackedVector2Array([Vector2(0, 240), Vector2(1280, 60)]))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var tip := _mk_label(menu_ui, "←/→ 或 A/D 变道     SPACE 跳跃\n躲开红色路障 · 收集能量方块", 26, Color(0.85, 0.85, 1.0), PackedVector2Array([Vector2(0, 420), Vector2(1280, 80)]))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var go := _mk_label(menu_ui, "点击 或 按任意键 开始", 30, C_MAGENTA, PackedVector2Array([Vector2(0, 560), Vector2(1280, 50)]))
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_best_menu = _mk_label(menu_ui, "历史最高 0", 22, Color(0.65, 0.85, 1.0), PackedVector2Array([Vector2(0, 620), Vector2(1280, 40)]))
	lbl_best_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_best_menu.set_anchors_preset(Control.PRESET_TOP_WIDE)

	# 结算面板
	dead_ui = Control.new()
	dead_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	dead_ui.visible = false
	ui.add_child(dead_ui)
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.01, 0.09, 0.88)
	sb.border_color = C_MAGENTA
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(430, 300)
	panel.position = Vector2(640 - 215, 360 - 150)
	dead_ui.add_child(panel)
	var t := _mk_label(panel, "撞 毁", 46, C_RED, PackedVector2Array([Vector2(0, 24), Vector2(430, 60)]))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_score = _mk_label(panel, "得分 0", 58, Color(1, 1, 1), PackedVector2Array([Vector2(0, 90), Vector2(430, 80)]))
	dead_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_best = _mk_label(panel, "最高 0", 24, Color(0.65, 0.85, 1.0), PackedVector2Array([Vector2(0, 172), Vector2(430, 36)]))
	dead_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_badge = _mk_label(panel, "★ 新纪录 ★", 26, Color(1, 0.8, 0.2), PackedVector2Array([Vector2(0, 148), Vector2(430, 32)]))
	new_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var again := _mk_label(panel, "按 R 或点击 重新开始", 24, C_CYAN, PackedVector2Array([Vector2(0, 232), Vector2(430, 40)]))
	again.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 菜单阶段隐藏 HUD 数字
	lbl_score.visible = false
	lbl_best.visible = false
	lbl_speed.visible = false
	lbl_orbs.visible = false

var lbl_best_menu: Label

# ---------------- 音频 ----------------
func _build_audio() -> void:
	var music := AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://assets/music_loop.wav")
	if stream:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2   # 16bit mono 帧数
		music.stream = stream
	music.volume_db = -7.0
	add_child(music)
	music.play()

	snd_pickup = _mk_sfx("res://assets/sfx_pickup.wav", -4.0)
	snd_jump = _mk_sfx("res://assets/sfx_jump.wav", -6.0)
	snd_lane = _mk_sfx("res://assets/sfx_lane.wav", -10.0)
	snd_crash = _mk_sfx("res://assets/sfx_crash.wav", -2.0)

func _mk_sfx(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	add_child(p)
	return p

# ---------------- 存档 / 参数 ----------------
func _load_best() -> void:
	var f := FileAccess.open("user://neonrush.dat", FileAccess.READ)
	if f:
		best = f.get_32()
	_sync_best_labels()

func _save_best() -> void:
	var f := FileAccess.open("user://neonrush.dat", FileAccess.WRITE)
	if f:
		f.store_32(best)

func _sync_best_labels() -> void:
	lbl_best.text = "最高 %d" % best
	lbl_best_menu.text = "历史最高 %d" % best

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			qa_dir = a.substr(13)
			DirAccess.make_dir_recursive_absolute(qa_dir)

func _qa_run_start() -> void:
	if not qa_started:
		qa_started = true
		_start_run()

# ---------------- 输入 ----------------
func _unhandled_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed
	var key := 0
	if event is InputEventKey and event.pressed and not event.echo:
		key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if state == "menu":
		if clicked or key != 0:
			_start_run()
		return
	if state == "run":
		if key in [KEY_A, KEY_LEFT]:
			_move_lane(-1)
		elif key in [KEY_D, KEY_RIGHT]:
			_move_lane(1)
		elif key in [KEY_SPACE, KEY_W, KEY_UP]:
			_jump()
		return
	if state == "dead" and dead_timer > 0.8:
		if clicked or key in [KEY_R, KEY_SPACE, KEY_ENTER]:
			_restart()

func _move_lane(dir: int) -> void:
	var n := clampi(lane + dir, 0, 2)
	if n != lane:
		lane_from = lane
		lane = n
		lane_t = 0.0
		snd_lane.play()

func _jump() -> void:
	if on_ground:
		jump_v = JUMP_V
		on_ground = false
		snd_jump.play()

func _start_run() -> void:
	state = "run"
	speed = BASE_SPEED
	menu_ui.visible = false
	lbl_score.visible = true
	lbl_best.visible = true
	lbl_speed.visible = true
	lbl_orbs.visible = true

func _restart() -> void:
	_clear_active()
	score = 0
	orbs = 0
	dist = 0.0
	speed = BASE_SPEED
	lane = 1
	lane_from = 1
	lane_t = 1.0
	player_y = HOVER_Y
	jump_v = 0.0
	on_ground = true
	shake = 0.0
	dead_timer = 0.0
	player_model.visible = true
	dead_ui.visible = false
	state = "run"
	Engine.time_scale = 1.0

func _clear_active() -> void:
	for o in obstacles_active:
		o.node.visible = false
		obstacle_pool.append(o)
	obstacles_active.clear()
	for o in orbs_active:
		o.node.visible = false
		orb_pool.append(o)
	orbs_active.clear()

# ---------------- 主循环 ----------------
func _process(delta: float) -> void:
	var dt := delta
	menu_t += dt

	if state == "run":
		speed = minf(MAX_SPEED, speed + 0.62 * dt)
		dist += speed * dt
		score = int(dist) + orbs * 30
		since_spawn += speed * dt
		if since_spawn > _spawn_gap():
			since_spawn = 0.0
			_spawn_pattern()
	elif state == "menu":
		speed = 7.0

	# 玩家横向插值 / 重力
	lane_t = minf(1.0, lane_t + dt / 0.14)
	var px := lerpf(LANE_X[lane_from], LANE_X[lane], smoothstep(0.0, 1.0, lane_t))
	if not on_ground or player_y > HOVER_Y:
		jump_v -= GRAVITY * dt
		player_y += jump_v * dt
		if player_y <= HOVER_Y:
			player_y = HOVER_Y
			jump_v = 0.0
			on_ground = true

	# 滚动世界
	var move := speed * dt
	_scroll_segments(move)
	_scroll_buildings(move * 0.4)
	_scroll_streaks(move * 1.7, dt)
	_scroll_obstacles(move, dt)
	_scroll_orbs(move, dt)

	# 玩家视觉
	player.position = Vector3(px, player_y, 0)
	player_model.position.y = sin(menu_t * 7.0) * 0.05 + 0.1
	player_model.rotation_degrees.z = (LANE_X[lane] - px) * -14.0
	player_model.rotation_degrees.y = (LANE_X[lane] - px) * -10.0
	var bank := clampf((LANE_X[lane] - px) * -0.6, -1, 1)
	var pulse := 4.5 + sin(menu_t * 26.0) * 1.8 + (speed - BASE_SPEED) * 0.08
	for em in ship_engine_mats:
		em.emission_energy_multiplier = pulse

	# 相机
	var target_pos := Vector3(px * 0.5, 3.3 + (player_y - HOVER_Y) * 0.32, 8.2)
	cam.position = cam.position.lerp(target_pos, minf(1.0, dt * 8.0))
	if shake > 0.01:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake
		shake = maxf(0.0, shake - dt * 2.4)
	cam.fov = lerpf(cam.fov, 72.0 + (speed - BASE_SPEED) * 0.55, minf(1.0, dt * 3.0))
	cam.rotation_degrees.z = lerpf(cam.rotation_degrees.z, bank * 1.6, minf(1.0, dt * 6.0))

	# HUD
	if state == "run":
		lbl_score.text = str(score)
		lbl_speed.text = "速度 %d km/h" % int(speed * 7.0)
		lbl_orbs.text = "◆ %d" % orbs

	if state == "dead":
		dead_timer += dt

	# QA 截图
	if qa_dir != "":
		qa_t += dt
		if qa_t > 1.2:
			_qa_run_start()
		if state == "run":
			_autopilot()
		if qa_i < qa_times.size() and qa_t >= qa_times[qa_i]:
			_take_shot(qa_i)
			qa_i += 1
		if qa_t > 9.5:
			get_tree().quit()

func _spawn_gap() -> float:
	return lerpf(16.0, 10.5, (speed - BASE_SPEED) / (MAX_SPEED - BASE_SPEED))

# ---------------- 道路滚动 ----------------
func _scroll_segments(move: float) -> void:
	for seg in seg_nodes:
		seg.position.z += move
		if seg.position.z > SEG_LEN:
			seg.position.z -= SEG_LEN * SEG_COUNT
		if seg.has_meta("arch"):
			seg.get_meta("arch").visible = seg.position.z < -5.0

func _scroll_buildings(move: float) -> void:
	for b in buildings:
		b.position.z += move
		if b.position.z > 50:
			b.position.z -= 290.0
			b.scale = Vector3.ONE * randf_range(0.8, 1.6)

func _scroll_streaks(move: float, dt: float) -> void:
	for s in streaks:
		s.position.z += move
		if s.position.z > 12:
			s.position.z = -95.0
			s.position.x = randf_range(5.5, 11.0) * (1 if randi() % 2 == 0 else -1)
			s.position.y = randf_range(0.5, 2.8)

# ---------------- 生成器 ----------------
func _obstacle_new() -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	return {"node": node, "kind": "tall", "lanes": [1], "counted": false}

func _obstacle_setup(o: Dictionary, kind: String, lanes: Array) -> void:
	o.kind = kind
	o.lanes = lanes
	o.counted = false
	o.node.visible = true
	for c in o.node.get_children():
		c.queue_free()
	var m: MeshInstance3D
	if kind == "low":
		m = _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(C_ORANGE, 3.4))
		m.mesh.size = Vector3(2.3, 0.9, 0.5)
		m.position = Vector3(LANE_X[lanes[0]], 0.45, 0)
		o.node.add_child(m)
		var glow := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(Color(1.0, 0.8, 0.3), 5.0))
		glow.mesh.size = Vector3(2.4, 0.08, 0.56)
		glow.position = Vector3(LANE_X[lanes[0]], 0.94, 0)
		o.node.add_child(glow)
	elif kind == "tall":
		m = _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(C_RED, 3.2))
		m.mesh.size = Vector3(2.2, 3.4, 0.5)
		m.position = Vector3(LANE_X[lanes[0]], 1.7, 0)
		o.node.add_child(m)
		var core := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(Color(1.0, 0.9, 0.9), 6.0))
		core.mesh.size = Vector3(0.12, 3.4, 0.54)
		core.position = Vector3(LANE_X[lanes[0]], 1.7, 0)
		o.node.add_child(core)
	else: # wide
		m = _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(C_RED, 3.0))
		m.mesh.size = Vector3(5.0, 2.7, 0.5)
		m.position = Vector3((LANE_X[lanes[0]] + LANE_X[lanes[1]]) / 2.0, 1.35, 0)
		o.node.add_child(m)
		for lx in lanes:
			var post := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(Color(1.0, 0.85, 0.5), 5.0))
			post.mesh.size = Vector3(0.1, 2.7, 0.54)
			post.position = Vector3(LANE_X[lx], 1.35, 0)
			o.node.add_child(post)

func _orb_new() -> Dictionary:
	var node := Node3D.new()
	var m := _mesh(MeshInstance3D.new(), BoxMesh.new(), _mat_emissive(C_CYAN, 6.0))
	m.mesh.size = Vector3(0.52, 0.52, 0.52)
	m.rotation_degrees = Vector3(45, 45, 0)
	node.add_child(m)
	var inner := _mesh(MeshInstance3D.new(), SphereMesh.new(), _mat_emissive(Color(0.8, 1.0, 1.0), 8.0))
	inner.mesh.radius = 0.16
	inner.mesh.height = 0.32
	node.add_child(inner)
	add_child(node)
	return {"node": node, "taken": false}

func _spawn_pattern() -> void:
	var r := randf()
	if r < 0.42:
		# 单障碍
		var kinds := ["low", "tall", "wide"]
		var kind: String = kinds[randi() % 3]
		var l := randi() % 3
		if kind == "wide":
			var lanes: Array = [0, 1] if l <= 1 else [1, 2]
			_spawn_obstacle(kind, lanes)
			if randf() < 0.6:
				var free := 2 if l <= 1 else 0
				for i in range(3):
					_spawn_orb(free, -2.0 - i * 2.0, 1.0)
		else:
			_spawn_obstacle(kind, [l])
			# low 障碍上方放一道能量弧引导跳跃
			if kind == "low" and randf() < 0.7:
				for i in range(3):
					_spawn_orb(l, -2.0 - i * 2.0, 1.6 + sin(i / 2.0 * PI) * 0.9)
	elif r < 0.78:
		# 双障碍必留一条活路
		var open := randi() % 3
		var others := [0, 1, 2]
		others.erase(open)
		if others[1] - others[0] == 1:
			_spawn_obstacle("wide", others)
		else:
			_spawn_obstacle("tall", [others[0]])
			_spawn_obstacle("tall", [others[1]])
		# 能量线在活路
		if randf() < 0.8:
			for i in range(4):
				_spawn_orb(open, -2.0 - i * 2.2, 1.0)
	else:
		# 纯能量斜线
		var l2 := randi() % 3
		for i in range(6):
			_spawn_orb(l2, -1.5 - i * 2.1, 1.0 + i * 0.14)

func _spawn_obstacle(kind: String, lanes: Array) -> void:
	var o: Dictionary
	if obstacle_pool.size() > 0:
		o = obstacle_pool.pop_back()
	else:
		o = _obstacle_new()
	_obstacle_setup(o, kind, lanes)
	o.node.position.z = SPAWN_Z
	obstacles_active.append(o)

func _spawn_orb(lane_i: int, dz: float, y: float) -> void:
	var o: Dictionary
	if orb_pool.size() > 0:
		o = orb_pool.pop_back()
	else:
		o = _orb_new()
	o.taken = false
	o.node.visible = true
	o.node.position = Vector3(LANE_X[lane_i], y, SPAWN_Z + dz)
	orbs_active.append(o)

# ---------------- 障碍 / 能量 ----------------
func _scroll_obstacles(move: float, dt: float) -> void:
	for i in range(obstacles_active.size() - 1, -1, -1):
		var o: Dictionary = obstacles_active[i]
		var z: float = o.node.position.z + move
		o.node.position.z = z
		# 近身判定
		if state == "run" and absf(z) < 0.85:
			var covered := false
			for l in o.lanes:
				if absf(player.position.x - LANE_X[l]) < 1.15:
					covered = true
					break
			if covered:
				if o.kind == "low":
					if player_y < 1.5:
						_die()
				else:
					_die()
		# 贴脸奖励
		if not o.counted and z >= 0.0:
			o.counted = true
			if state == "run":
				var nearest := 99.0
				for l in o.lanes:
					nearest = minf(nearest, absf(player.position.x - LANE_X[l]))
				if nearest > 1.15 and nearest < 2.9:
					score += 15
					_popup("贴脸 +15", C_ORANGE)
		if z > 14:
			o.node.visible = false
			obstacles_active.remove_at(i)
			obstacle_pool.append(o)

func _scroll_orbs(move: float, dt: float) -> void:
	for i in range(orbs_active.size() - 1, -1, -1):
		var o: Dictionary = orbs_active[i]
		var z: float = o.node.position.z + move
		o.node.position.z = z
		o.node.rotation.y += dt * 3.0
		o.node.position.y += sin(menu_t * 5.0 + z) * dt * 0.4
		if state == "run" and not o.taken and absf(z) < 1.0:
			if absf(player.position.x - o.node.position.x) < 1.0 and absf(player_y + 0.3 - o.node.position.y) < 1.3:
				o.taken = true
				o.node.visible = false
				orbs += 1
				score += 30
				snd_pickup.play()
				_burst(o.node.position, C_CYAN, 18)
				_popup("+30", C_CYAN)
		if z > 14:
			o.node.visible = false
			orbs_active.remove_at(i)
			orb_pool.append(o)

# ---------------- 死亡 ----------------
func _die() -> void:
	if state != "run":
		return
	state = "dead"
	dead_timer = 0.0
	shake = 0.55
	snd_crash.play()
	_burst(player.position, C_MAGENTA, 40)
	_burst(player.position, C_ORANGE, 26)
	player_model.visible = false
	Engine.time_scale = 0.28
	var t := get_tree().create_timer(0.55, true, false, true)
	t.timeout.connect(func(): Engine.time_scale = 1.0)
	var is_record := score > best
	if is_record:
		best = score
		_save_best()
		_sync_best_labels()
	dead_score.text = "得分 %d" % score
	dead_best.text = "最高 %d    能量 %d" % [best, orbs]
	new_badge.visible = is_record
	dead_ui.visible = true

# ---------------- 特效 ----------------
func _burst(pos: Vector3, color: Color, n: int) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -14, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = color
	p.process_material = pm
	var mesh := _mesh(MeshInstance3D.new(), SphereMesh.new(), _mat_emissive(color, 5.0))
	mesh.mesh.radius = 0.09
	mesh.mesh.height = 0.18
	p.draw_pass_1 = mesh.mesh
	p.amount = n
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.9
	p.position = pos
	p.emitting = true
	add_child(p)
	var t := get_tree().create_timer(1.4)
	t.timeout.connect(func():
		p.queue_free()
	)

func _popup(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", hud_font)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	ui.add_child(l)
	var base := Vector2(560 + randf_range(-40, 40), 330)
	l.position = base
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", base.y - 70.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

# ---------------- 自动驾驶 + 截图（QA） ----------------
func _autopilot() -> void:
	# 标记 55m 内的危险道（低栏可跳过不算）
	var danger := {}
	for o in obstacles_active:
		var z: float = o.node.position.z
		if z < 2.0 and z > -55.0 and o.kind != "low":
			for l in o.lanes:
				danger[l] = minf(danger.get(l, 99.0), -z)
	# 选距离当前道最近的安全道
	var best_c := -1
	var best_d := 99
	for c in range(3):
		if not danger.has(c) and absi(c - lane) < best_d:
			best_c = c
			best_d = absi(c - lane)
	if best_c >= 0 and best_c != lane and lane_t >= 1.0:
		var step := 1 if best_c > lane else -1
		if not danger.has(lane + step):
			_move_lane(step)
	# 低栏跳跃
	for o in obstacles_active:
		if o.kind == "low" and o.node.position.z > -9.0 and o.node.position.z < -2.0:
			for l in o.lanes:
				if absf(LANE_X[lane] - LANE_X[l]) < 1.0:
					_jump()

func _take_shot(i: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(qa_dir + "/qa_%d.png" % i)
	print("[QA] saved qa_%d.png  score=%d speed=%.1f" % [i, score, speed])

# ---------------- 工具 ----------------
func _mesh(mi: MeshInstance3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	mi.mesh = mesh
	if mat and mesh is PrimitiveMesh:
		mesh.material = mat
	return mi

func _mat(albedo: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = rough
	return m

func _mat_emissive(color: Color, energy: float, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.5
	return m
