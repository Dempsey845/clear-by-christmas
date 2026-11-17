class_name JobHUD
extends CanvasLayer

signal accept_requested
signal save_requested
signal load_requested
signal phone_toggled(open: bool)

const PHONE_HIDDEN := 460.0

@onready var phone: PanelContainer = %Phone
@onready var progress: ProgressBar = %ClearanceBar

var phone_open := false
var _phone_tween: Tween
var _prior_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _day := 1
var _clock := "08:00"


func _ready() -> void:
	%Accept.pressed.connect(func() -> void:
		close_phone()
		accept_requested.emit()
	)
	%Save.pressed.connect(func() -> void: save_requested.emit())
	%Load.pressed.connect(func() -> void: load_requested.emit())
	%JobsTab.pressed.connect(_show_history.bind(false))
	%HistoryTab.pressed.connect(_show_history.bind(true))
	$NoticeTimer.timeout.connect(clear_notice)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("job_phone") or (phone_open and event.is_action_pressed("pause")):
		_set_phone_open(not phone_open)
		get_viewport().set_input_as_handled()


func close_phone() -> void:
	_set_phone_open(false)


func set_balance(amount: int) -> void:
	%Balance.text = "Balance  £%d" % amount


func set_day(day: int, completed: int, total: int, last_day: int) -> void:
	_day = day
	set_clock(_clock)
	%DailyCount.text = "Jobs  %d / %d" % [completed, total]
	var finished := completed >= total
	%DayStatus.text = "Go home and sleep to get tomorrow’s jobs."
	if finished and day == last_day:
		%DayStatus.text = "Christmas jobs complete!"
	%DayStatus.visible = finished


func set_clock(clock: String) -> void:
	_clock = clock
	%Date.text = "December %d  ·  %s" % [_day, _clock]


func set_history(entries: Array[Dictionary]) -> void:
	var lines := PackedStringArray()
	for index in range(entries.size() - 1, -1, -1):
		var entry := entries[index]
		lines.append("%s  ·  +£%d\nDecember %d" % [entry.address, entry.pay, entry.day])
	%HistoryText.text = "\n\n".join(lines) if not lines.is_empty() else "No completed jobs yet."


func show_offer(job: SnowJob, area: float, volume: float) -> void:
	_show_job_details(job, area, volume)
	%PhoneHeading.text = "Job available"
	%Accept.show()
	%PhoneKey.text = "J   Accept a job"
	%ProgressPanel.hide()


func show_assignment(job: SnowJob, area: float, volume: float) -> void:
	_show_job_details(job, area, volume)
	%PhoneHeading.text = "Job in progress"
	%Accept.hide()
	%PhoneKey.text = "J   Job phone"
	%JobTitle.text = job.address
	%ProgressPanel.show()


func _show_job_details(job: SnowJob, area: float, volume: float) -> void:
	%Client.text = job.client_name
	%Address.text = job.address
	%Payout.text = "£%d" % job.pay
	%Lawn.text = "%.1f m² lawn  ·  Clear %d%%" % [area, job.required_clear_percent]
	%Snow.text = "%.2f m³ of snowfall" % volume


func set_progress(fraction: float, remaining: float, required: int) -> void:
	progress.value = fraction * 100.0
	%ProgressText.text = "%d%% cleared  ·  %d%% needed" % [floori(fraction * 100.0), required]
	%Remaining.text = "%.2f m³ left" % remaining


func show_day_finished(is_christmas: bool) -> void:
	%PhoneHeading.text = "Christmas jobs complete" if is_christmas else "Today’s jobs are done"
	%Client.text = ""
	%Address.text = ""
	%Lawn.text = "Go home and sleep to receive tomorrow’s jobs." if not is_christmas else "You cleared every Christmas job."
	%Snow.text = ""
	%Payout.text = ""
	%Accept.hide()
	%PhoneKey.text = "J   Job phone"
	%ProgressPanel.hide()


func notify_payment(job: SnowJob) -> void:
	%Notice.text = "%s cleared  ·  +£%d" % [job.address, job.pay]
	%Notice.show()
	$NoticeTimer.start()


func clear_notice() -> void:
	%Notice.hide()


func set_save_status(message: String) -> void:
	%SaveStatus.text = message


func _show_history(show_history: bool) -> void:
	%JobDetails.visible = not show_history
	%HistoryScroll.visible = show_history


func _set_phone_open(open: bool) -> void:
	if open == phone_open:
		return
	phone_open = open
	phone_toggled.emit(open)
	if _phone_tween != null:
		_phone_tween.kill()
	if not open:
		Input.mouse_mode = _prior_mouse_mode
		phone.hide()
		return
	_prior_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	phone.position.y = PHONE_HIDDEN
	phone.show()
	_phone_tween = create_tween()
	_phone_tween.tween_property(phone, "position:y", 0.0, 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
