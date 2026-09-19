extends Camera3D
## CameraFollow — Câmera HD-2D perspectiva que segue o jogador local suavemente.
##
## Perspectiva ~20° de inclinação (pitch) para baixo, FOV 52°.
## Offset: Vector3(0, 9, 20) atrás/acima do jogador.
## Follow com lerp suave no _physics_process.

## Velocidade de seguimento (interpolação suave).
@export var follow_speed: float = 5.0

## Offset da câmera em relação ao alvo (espaço local: x=lateral, y=altura, z=atrás).
@export var offset: Vector3 = Vector3(0.0, 9.0, 20.0)

## Referência ao nó alvo (preenchida por AlvidaHold após spawn do jogador local).
var target: Node3D = null

func _ready() -> void:
	# Garante perspectiva com as configurações corretas.
	projection = PROJECTION_PERSPECTIVE
	fov        = 52.0
	near       = 0.1
	far        = 200.0
	# Rotação fixa: pitch ~24° para baixo (atan(9/20) ≈ 24°).
	rotation_degrees = Vector3(-24.0, 0.0, 0.0)

func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	# Posição desejada: alvo + offset na orientação da câmera (sem roll/yaw).
	var desired_pos := target.global_position + offset
	global_position = global_position.lerp(desired_pos, follow_speed * delta)
