# libimobiledevice.gd
#
# API for libimobiledevice suite of tools
#
# - get all connected device uuids:
#	`idevice_id --list`
#
# - get device information:
#	`ideviceinfo --udid <UUID>`
#	- parse keys: ProductType, ProductVersion, DeviceColor, DeviceName
#
# - mount developer image for running/debugging an app:
#	`ideviceimagemounter --udid <UUID> <IMAGE> <IMAGE_SIGNATURE>`
#	- You can check for developer images from
#		`xcode-select --print-path`/Platforms/iPhoneOS.platform/DeviceSupport/<ProductVersion>/DeveloperDiskImage.dmg{.signature}
#	- if there is no device support for <ProductVersion> tell user to update xcode
#
# - install an app bundle:
#	`ideviceinstaller --udid <UUID> --install <BUNDLE_PATH>`
#	`ideviceinstaller --udid <UUID> --upgrade <BUNDLE_PATH>`
#
# - launch an app on a device:
#	`idevicedebug --udid <UUID> [--env <KEY>=<VAL>...] run <BUNDLE_ID> <RUN_ARGS...>`
extends 'DeployTool.gd'


# ------------------------------------------------------------------------------
#                                     Constants
# ------------------------------------------------------------------------------


const DOMAIN = 'libimobiledevice'
const DEFAULT_TOOL_DIR = '/usr/local/bin'
const UDID_ARG_SPEC = '--udid'
const DEVICE_INFO_KEY_MAP = {
	DeviceName = 'name',
	DeviceColor = 'color',
	ProductType = 'type', # or use DeviceClass?
	ProductVersion = 'version'
}


# ------------------------------------------------------------------------------
#                                     Variables
# ------------------------------------------------------------------------------


var _shell = Shell.new()


# ------------------------------------------------------------------------------
#                                     Overrides
# ------------------------------------------------------------------------------


func get_default_path():
	return DEFAULT_TOOL_DIR


func get_name():
	return 'libimobiledevice'


# ------------------------------------------------------------------------------
#                                      Methods
# ------------------------------------------------------------------------------


func tool_get_installer():
	return get_path().plus_file('ideviceinstaller')

func tool_get_image_mounter():
	return get_path().plus_file('ideviceimagemounter')

func tool_get_debug():
	return get_path().plus_file('idevicedebug')

func tool_get_info():
	return get_path().plus_file('ideviceinfo')

func tool_get_id():
	return get_path().plus_file('idevice_id')


func get_connected_device_ids():
	var id_tool = tool_get_id()
	var exec_args = ['--list']
	_log.verbose('Getting connected device ids: '+str(id_tool,' ',exec_args))
	var result = _shell.execute(
		id_tool, exec_args,
		DOMAIN
	)
	if result.code != OK:
		_log.error('Error<%s>: Failed to get connected device ids: %s'%[result.code, result.output])
		return []
	var ids = result.get_stdout_lines()
	_log.debug(str('Connected device ids: ', ids))
	return ids


func get_device_info(device_id):
	var info_tool = tool_get_info()
	var exec_args = [UDID_ARG_SPEC, device_id]
	_log.verbose('Getting device<%s> info: %s'%[device_id,str(info_tool,' ',exec_args)])
	var result = _shell.execute(
		info_tool, exec_args,
		DOMAIN
	)
	_log.verbose(str('Getting device info code<%s>'%result.code, ' output: ' ,result.output))
	if result.code != OK:
		_log.error('Error<%s>: Failed to get device<%s> info:\n%s'%[result.code, device_id, result.output])
		return null
	var info = _parse_device_info_output(result.get_stdout_lines())
	if info != null: info.id = device_id
	_log.debug(str('Parsed device: ', Device.new().ToDict(info)))
	return info

func _parse_device_info_output(output):
	var info = Device.new()
	for line in output:
		for key in DEVICE_INFO_KEY_MAP:
			if not line.begins_with(key):
				continue
			var value = line.right(str(key, ': ').length())
			if key == 'ProductType':
				if value.begins_with('iPad'):
					info.type = Device.Type.iPad
				elif value.begins_with('iPhone'):
					info.type = Device.Type.iPhone
			else:
				info.set(DEVICE_INFO_KEY_MAP[key], value)
			break
	return info


func mount_developer_image(device_id, developer_img_path, developer_img_sig):
	_log.verbose('Mounting developer image<%s> to device<%s>'%[developer_img_path, device_id])
	if not File.new().file_exists(developer_img_path):
		_log.error('Error<%s>: Developer image path not found: %s'%[ERR_FILE_NOT_FOUND, developer_img_path])
		return ERR_FILE_NOT_FOUND
	if not File.new().file_exists(developer_img_sig):
		_log.error('Error<%s>: Developer image signature path not found: %s'%[ERR_FILE_NOT_FOUND, developer_img_sig])
		return ERR_FILE_NOT_FOUND
	var img_mount_tool = tool_get_image_mounter()
	var exec_args = [UDID_ARG_SPEC, device_id, developer_img_path, developer_img_sig]
	_log.verbose(str('Mount dev img command: ', img_mount_tool, ' ', exec_args))
	var result = _shell.execute(
		img_mount_tool, exec_args,
		DOMAIN
	)
	_log.verbose(str('Mount dev img code<%s>'%result.code, ' output: ', result.output))
	if result.code != OK:
		_log.error('Error<%s>: Failed to mount developer image on device<%s>\n%s'%[result.code, device_id, result.output])
		return FAILED
	return OK


func install_app(device_id, app_bundle_path):
	_log.verbose('Installing app at path<%s> to device<%s>'%[app_bundle_path, device_id])
	if not Directory.new().dir_exists(app_bundle_path):
		_log.error('Error<%s>: App bundle path<%s> not found'%[ERR_FILE_NOT_FOUND, app_bundle_path])
		return ERR_FILE_NOT_FOUND
	var install_tool = tool_get_installer()
	var exec_args = [UDID_ARG_SPEC, device_id, '--install', app_bundle_path]
	_log.verbose(str('Install app command: ', install_tool, ' ', exec_args))
	var result = _shell.execute(
		tool_get_installer(), exec_args,
		DOMAIN
	)
	_log.verbose(str('Install app code<%s>'%result.code, ' output: ', result.output))
	if result.code != OK:
		_log.error('Error<%s>: Failed to install app<%s> to device<%s>:\n%s'%[result.code, app_bundle_path, device_id, result.output])
		return FAILED
	return OK


func launch_app(device_id, app_bundle_id, arguments=[], environment={}):
	_log.verbose('Launching app<%s> on device<%s> with arguments<%s> and environment<%s>'%[app_bundle_id, device_id, arguments, environment])
	var debug_tool = tool_get_debug()
	var exec_args = _build_launch_app_args(device_id, app_bundle_id, arguments, environment)
	_log.verbose(str('Launch app command: ', debug_tool, ' ', exec_args))
	var result = _shell.execute(
		tool_get_debug(), exec_args,
		DOMAIN
	)
	_log.verbose(str('Launch app code<%s>'%result.code, ' output: ', result.output))
	if result.code != OK:
		var _msgs = [app_bundle_id, device_id, arguments, environment, result.output]
		_log.error('Error<%s>: Failed to launch bundle<%s> on device<%s> with arguments<%s> and environment<%s>: '%_msgs)
		return FAILED
	return OK

func _build_launch_app_args(device_id, app_bundle_id, arguments, environment):
	var args = [UDID_ARG_SPEC, device_id]
	args.resize(arguments.size() + (environment.size() * 2))
	for key in environment:
		args.append('--env')
		args.append(str(key, '=', environment[key]))
	args.append('run')
	args.append(app_bundle_id)
	for run_arg in arguments:
		args.append(run_arg)
	return args

