extends Node
## NetworkManager — Autoload singleton
## Gerencia conexão com Nakama: autenticação Device ID, join match, envio de intents e recepção de snapshots.
## Requer o addon GDNakama em addons/com.heroiclabs.nakama (autoload Nakama).

signal connected
signal logged_in(session)
signal profile_loaded(profile_data)
signal match_joined(match_id)
signal match_state_received(op_code, data, presence)

var _client: NakamaClient
var _session: NakamaSession
var _socket: NakamaSocket
var _match_id: String = ""

## Dados de aparência do personagem local (preenchidos pelo CharacterCreator).
var appearance_data: Dictionary = {}

## Último perfil recebido — AlvidaHold usa para catch-up se o sinal já passou.
var last_profile: Dictionary = {}

## ID do jogador local (preenchido após login).
var local_user_id: String = ""

## Slot de destino para o CharacterCreator (definido pela CharacterSelect).
## -1 = sem slot (modo legado); >=0 = criação de personagem via CharacterSelect.
var target_slot: int = -1

# ─── Lifecycle ──────────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_and_login()

func get_match_id() -> String:
	return _match_id

func is_in_match() -> bool:
	return _match_id != "" and _socket != null

# ─── Conexão e autenticação ─────────────────────────────────────────────────

func _connect_and_login() -> void:
	_client = Nakama.create_client("defaultkey", "127.0.0.1", 7350, "http")

	var device_id: String = OS.get_unique_id()
	_session = await _client.authenticate_device_async(device_id)

	if _session.is_exception():
		push_error("[NetworkManager] Falha no login Device ID: " + str(_session.get_exception()))
		return

	local_user_id = _session.user_id
	emit_signal("logged_in", _session)

	_socket = Nakama.create_socket_from(_client)
	var conn_result = await _socket.connect_async(_session)

	if conn_result != null and conn_result.is_exception():
		push_error("[NetworkManager] Falha na conexão do socket: " + str(conn_result.get_exception()))
		return

	emit_signal("connected")

	_socket.received_match_state.connect(_on_match_state_received)
	_socket.received_error.connect(_on_socket_error)
	_socket.closed.connect(_on_socket_closed)
	# Não carrega perfil automaticamente — CharacterSelect chama list_characters().

# ─── Multi-slot character APIs ──────────────────────────────────────────────

## Lista os 3 slots de personagens do jogador.
## Retorna Array[Variant] de 3 elementos: null ou { name, level, appearance }.
func list_characters() -> Array:
	if _session == null or _session.is_exception():
		return [null, null, null]
	var result = await _client.rpc_async(_session, "rpc_list_characters", "")
	if result.is_exception():
		push_error("[NetworkManager] rpc_list_characters falhou: " + str(result.get_exception()))
		return [null, null, null]
	var parsed: Variant = JSON.parse_string(result.payload)
	# O servidor retorna {"slots": [null|{...}, ...]} — extrair o array interno.
	if parsed and parsed is Dictionary:
		var slots: Variant = parsed.get("slots", [])
		if slots is Array:
			# Garantir sempre 3 elementos
			var out: Array = [null, null, null]
			for i in mini(slots.size(), 3):
				out[i] = slots[i]
			return out
	return [null, null, null]

## Cria um novo personagem no slot indicado.
## Retorna o perfil criado ou {} em caso de erro.
func create_character(slot: int, char_name: String, appearance: Dictionary) -> Dictionary:
	if _session == null or _session.is_exception():
		return {}
	var payload := JSON.stringify({"slot": slot, "name": char_name, "appearance": appearance})
	var result = await _client.rpc_async(_session, "rpc_create_character", payload)
	if result.is_exception():
		push_error("[NetworkManager] rpc_create_character falhou: " + str(result.get_exception()))
		return {}
	var parsed: Variant = JSON.parse_string(result.payload)
	if parsed and parsed is Dictionary:
		return parsed
	return {}

## Seleciona o personagem de um slot como ativo e carrega o perfil completo.
## Emite profile_loaded com o perfil retornado.
func select_character(slot: int) -> Dictionary:
	if _session == null or _session.is_exception():
		return {}
	var payload := JSON.stringify({"slot": slot})
	var result = await _client.rpc_async(_session, "rpc_select_character", payload)
	if result.is_exception():
		push_error("[NetworkManager] rpc_select_character falhou: " + str(result.get_exception()))
		return {}
	var parsed: Variant = JSON.parse_string(result.payload)
	if parsed and parsed is Dictionary:
		last_profile   = parsed
		appearance_data = parsed.get("appearance", {})
		emit_signal("profile_loaded", parsed)
		return parsed
	return {}

# ─── Perfil legado (mantido para compatibilidade) ───────────────────────────

## Salva aparência do personagem no servidor via RPC.
func save_profile_appearance(data: Dictionary) -> void:
	appearance_data = data
	if _session == null or _session.is_exception():
		push_warning("[NetworkManager] save_profile_appearance chamado sem sessão válida.")
		return
	var payload: String = JSON.stringify(data)
	var result = await _client.rpc_async(_session, "rpc_save_appearance", payload)
	if result.is_exception():
		push_error("[NetworkManager] RPC rpc_save_appearance falhou: " + str(result.get_exception()))

# ─── Match ───────────────────────────────────────────────────────────────────

## Entra no match AlvidaHold (chamar a partir da cena do mundo).
func join_match_if_needed() -> void:
	if is_in_match():
		return
	await _join_match()

func _join_match() -> void:
	# Solicita ao servidor o ID do match AlvidaHold_01.
	# O RPC rpc_get_alvida_match_id cria o match se não existir e retorna seu ID.
	var rpc_result = await _client.rpc_async(_session, "rpc_get_alvida_match_id", "")

	var match_id: String = ""
	if not rpc_result.is_exception() and rpc_result.payload != "":
		var data: Variant = JSON.parse_string(rpc_result.payload)
		if data and data is Dictionary and data.has("match_id"):
			match_id = str(data["match_id"])

	if match_id == "":
		push_error("[NetworkManager] Não foi possível obter o match ID do servidor.")
		return

	var join_result = await _socket.join_match_async(match_id)
	if join_result.is_exception():
		push_error("[NetworkManager] Falha ao entrar no match: " + str(join_result.get_exception()))
		return

	_match_id = join_result.match_id
	emit_signal("match_joined", _match_id)

# ─── Recepção de estado ──────────────────────────────────────────────────────

func _on_match_state_received(p_match_state: NakamaRTAPI.MatchData) -> void:
	var op_code: int = p_match_state.op_code
	# GDNakama já decodifica base64 → UTF-8 em MatchData.data (String).
	var data_str: String = p_match_state.data if p_match_state.data != null else ""
	var parsed: Variant = JSON.parse_string(data_str) if data_str != "" else {}
	if parsed == null:
		parsed = {}
	emit_signal("match_state_received", op_code, parsed, p_match_state.presence)

func _on_socket_error(p_error) -> void:
	push_error("[NetworkManager] Erro no socket: " + str(p_error))

func _on_socket_closed() -> void:
	push_warning("[NetworkManager] Socket fechado.")

# ─── Envio de intents ────────────────────────────────────────────────────────

## OpCode 1 — Movimento do jogador. Envia posição alvo e número de sequência.
func send_move_intent(x: float, y: float, seq: int) -> void:
	if _socket == null or _match_id == "":
		return
	var payload: String = IntentCodec.encode_move(x, y, seq)
	_socket.send_match_state_async(_match_id, 1, payload)

## OpCode 10 — Intenção de ataque. skill_id identifica a habilidade usada.
func send_attack_intent(skill_id: String, aim_x: float, aim_y: float) -> void:
	if _socket == null or _match_id == "":
		return
	var payload: String = IntentCodec.encode_attack(skill_id, aim_x, aim_y)
	_socket.send_match_state_async(_match_id, 10, payload)

## OpCode 21 — Intenção de equipar item.
func send_equip_intent(item_id: String) -> void:
	if _socket == null or _match_id == "":
		return
	var payload: String = IntentCodec.encode_equip(item_id)
	_socket.send_match_state_async(_match_id, 21, payload)

## OpCode 32 — Alocação de atributo (str, agi, int).
func send_allocate_stat(stat_name: String) -> void:
	if _socket == null or _match_id == "":
		return
	var payload: String = IntentCodec.encode_allocate_stat(stat_name)
	_socket.send_match_state_async(_match_id, 32, payload)
