class_name JobHUD
extends CanvasLayer

const PHONE_INSET := 0.0
const PHONE_HIDDEN := 430.0

@onready var phone: PanelContainer = %Phone
@onready var notice_timer: Timer = $NoticeTimer
@onready var progress: ProgressBar = %ClearanceBar

var _phone_open := false
var _phone_tween: Tween


func _ready() -> void:
	notice_timer.timeout.connect(_set_phone_open.bind(false))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("job_phone"):
		notice_timer.stop()
		_set_phone_open(not _phone_open)
		get_viewport().set_input_as_handled()


func set_balance(amount: int) -> void:
	%Balance.text = "Balance  £%d" % amount


func show_assignment(job: SnowJob, area: float, chunks: int, volume: float) -> void:
	%PhoneHeading.text = "New lawn job"
	%Client.text = job.client_name
	%Address.text = job.address
	%Payout.text = "£%d" % job.pay
	%Lawn.text = "%.0f m² lawn · %d %s" % [area, chunks, "chunk" if chunks == 1 else "chunks"]
	%Snow.text = "%.2f m³ of snow" % volume
	%JobTitle.text = job.address
	%ProgressPanel.show()
	progress.show()
	set_progress(0.0, volume, job.required_clear_percent)
	_notify()


func set_progress(fraction: float, remaining: float, required: int) -> void:
	progress.value = fraction * 100.0
	%ProgressText.text = "%d%% cleared  ·  %d%% needed" % [floori(fraction * 100.0), required]
	%Remaining.text = "%.2f m³ left" % remaining


func show_completed(job: SnowJob) -> void:
	%PhoneHeading.text = "Job complete"
	%Payout.text = "+£%d" % job.pay
	%Lawn.text = "Payment received"
	%Snow.text = ""
	%ProgressText.text = "Job complete  ·  +£%d" % job.pay
	%Remaining.text = ""
	_notify()


func show_no_requests() -> void:
	%PhoneHeading.text = "No pending jobs"
	%Client.text = ""
	%Address.text = ""
	%Payout.text = ""
	%Lawn.text = "All available requests are finished."
	%Snow.text = ""
	%ProgressPanel.hide()
	notice_timer.start()


func _notify() -> void:
	_set_phone_open(true)
	notice_timer.start()


func _set_phone_open(open: bool) -> void:
	if open == _phone_open:
		return
	_phone_open = open
	if _phone_tween != null:
		_phone_tween.kill()
	if open and not phone.visible:
		phone.position.y = PHONE_HIDDEN
		phone.show()
	_phone_tween = create_tween()
	_phone_tween.tween_property(phone, "position:y", PHONE_INSET if open else PHONE_HIDDEN, 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not open:
		_phone_tween.tween_callback(phone.hide)
