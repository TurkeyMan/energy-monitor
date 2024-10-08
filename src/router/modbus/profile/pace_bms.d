module router.modbus.profile.pace_bms;

import router.modbus.profile;

ModbusRegInfo[] paceBmsRegs()
{
	return [
	// Data acquisition
	ModbusRegInfo(40000, "i16", "current", "10mA", "A", Frequency.Realtime, "Current flow. Positive: Charging, Negative: Discharging"),
	ModbusRegInfo(40001, "u16", "packVoltage", "10mV", "V", Frequency.Medium, "Voltage of the pack"),
	ModbusRegInfo(40002, "u16", "stateOfCharge", "%", "%", Frequency.Medium, "State of Charge (SOC)"),
	ModbusRegInfo(40003, "u16", "stateOfHealth", "%", "%", Frequency.Low, "State of Health (SOH)"),
	ModbusRegInfo(40004, "u16", "remainCapacity", "10mAh", "Ah", Frequency.Medium, "Remaining battery capacity"),
	ModbusRegInfo(40005, "u16", "fullCapacity", "10mAh", "Ah", Frequency.Low, "Full battery capacity"),
	ModbusRegInfo(40006, "u16", "designCapacity", "10mAh", "Ah", Frequency.Constant, "Design capacity of the battery"),
	ModbusRegInfo(40007, "u16", "cycleCounts", null, null, Frequency.Low, "Number of battery cycle counts"),
	ModbusRegInfo(40009, "bf16", "warningFlag", null, null, Frequency.Medium, "Warning flags",
		["cellOV", "cellUV", "packOV", "packUV", "chargeOC", "dischargeOC", null, null, "chargeOT", "dischargeOT", "chargeUT", "dischargeUT", "envOT", "envUT", "mosfetOT", "socLow"],
		["Cell Overvoltage", "Cell Voltage Low", "Pack Overvoltage", "Pack Voltage Low", "Charging Overcurrent", "Discharging Overcurrent", null, null, "Charging Temp High", "Discharging Temp High", "Charging Temp Low", "Discharging Temp Low", "Environment Temp High", "Environment Temp Low", "MOSFET Temp High", "SOC Low"]),
	ModbusRegInfo(40010, "bf16", "protectionFlag", null, null, Frequency.Medium, "Protection flags",
		["cellOVProtect", "cellLVProtect", "packOVProtect", "packUVProtect", "chargeOCProtect", "dischargeOCProtect", "shortCircuitProtect", "chargerOVProtect", "chargeOTProtect", "dischargeOTProtect", "chargeUTProtect", "dischargeUTProtect", "mosfetOTProtect", "envOTProtect", "envUTProtect", null],
		["Cell Overvoltage", "Cell Voltage Low", "Pack Overvoltage", "Pack Voltage Low", "Charging Overcurrent", "Discharging Overcurrent", "Short Circuit", "Charger Overvoltage", "Charging Temp High", "Discharging Temp High", "Charging Temp Low", "Discharging Temp Low", "MOSFET Temp High", "Environment Temp High", "Environment Temp Low", null]),
	ModbusRegInfo(40011, "bf16", "statusFaultFlag", null, null, Frequency.Medium, "Status and fault flags",
		["chargeMosfetFault", "dischargeMosfetFault", "tempSensorFault", null, "cellFault", "samplingCommFault", null, null, "charging", "discharging", "chargMosfetOn", "dischargeMosfetOn", "chargingLimiterOn", null, "chargerInversed", "heaterOn"],
		["Charging MOSFET Fault", "Discharging MOSFET Fault", "Temperature Sensor Fault", null, "Battery Cell Fault", "Front End Sampling Communication Fault", null, null, "Charging", "Discharging", "Charging MOSFET On", "Discharging MOSFET On", "Charging Limiter On", null, "Charger Inversed", "Heater On"]),
	ModbusRegInfo(40012, "bf16", "balanceStatus", null, null, Frequency.Medium, "Balance status of the battery",
		["cellBalance1", "cellBalance2", "cellBalance3", "cellBalance4", "cellBalance5", "cellBalance6", "cellBalance7", "cellBalance8", "cellBalance9", "cellBalance10", "cellBalance11", "cellBalance12", "cellBalance13", "cellBalance14", "cellBalance15", "cellBalance16"],
		["Balancing cell 1", "Balancing cell 2", "Balancing cell 3", "Balancing cell 4", "Balancing cell 5", "Balancing cell 6", "Balancing cell 7", "Balancing cell 8", "Balancing cell 9", "Balancing cell 10", "Balancing cell 11", "Balancing cell 12", "Balancing cell 13", "Balancing cell 14", "Balancing cell 15", "Balancing cell 16"]),
	ModbusRegInfo(40015, "u16", "cellVoltage1", "mV", "V", Frequency.Medium, "Voltage of cell 1"),
	ModbusRegInfo(40016, "u16", "cellVoltage2", "mV", "V", Frequency.Medium, "Voltage of cell 2"),
	ModbusRegInfo(40017, "u16", "cellVoltage3", "mV", "V", Frequency.Medium, "Voltage of cell 3"),
	ModbusRegInfo(40018, "u16", "cellVoltage4", "mV", "V", Frequency.Medium, "Voltage of cell 4"),
	ModbusRegInfo(40019, "u16", "cellVoltage5", "mV", "V", Frequency.Medium, "Voltage of cell 5"),
	ModbusRegInfo(40020, "u16", "cellVoltage6", "mV", "V", Frequency.Medium, "Voltage of cell 6"),
	ModbusRegInfo(40021, "u16", "cellVoltage7", "mV", "V", Frequency.Medium, "Voltage of cell 7"),
	ModbusRegInfo(40022, "u16", "cellVoltage8", "mV", "V", Frequency.Medium, "Voltage of cell 8"),
	ModbusRegInfo(40023, "u16", "cellVoltage9", "mV", "V", Frequency.Medium, "Voltage of cell 9"),
	ModbusRegInfo(40024, "u16", "cellVoltage10", "mV", "V", Frequency.Medium, "Voltage of cell 10"),
	ModbusRegInfo(40025, "u16", "cellVoltage11", "mV", "V", Frequency.Medium, "Voltage of cell 11"),
	ModbusRegInfo(40026, "u16", "cellVoltage12", "mV", "V", Frequency.Medium, "Voltage of cell 12"),
	ModbusRegInfo(40027, "u16", "cellVoltage13", "mV", "V", Frequency.Medium, "Voltage of cell 13"),
	ModbusRegInfo(40028, "u16", "cellVoltage14", "mV", "V", Frequency.Medium, "Voltage of cell 14"),
	ModbusRegInfo(40029, "u16", "cellVoltage15", "mV", "V", Frequency.Medium, "Voltage of cell 15"),
	ModbusRegInfo(40030, "u16", "cellVoltage16", "mV", "V", Frequency.Medium, "Voltage of cell 16"),
	ModbusRegInfo(40031, "i16", "cellTemp1", "0.1°C", "°", Frequency.Medium, "Temperature of cell 1"),
	ModbusRegInfo(40032, "i16", "cellTemp2", "0.1°C", "°", Frequency.Medium, "Temperature of cell 2"),
	ModbusRegInfo(40033, "i16", "cellTemp3", "0.1°C", "°", Frequency.Medium, "Temperature of cell 3"),
	ModbusRegInfo(40034, "i16", "cellTemp4", "0.1°C", "°", Frequency.Medium, "Temperature of cell 4"),
	ModbusRegInfo(40035, "i16", "mosfetTemp", "0.1°C", "°", Frequency.Medium, "MOSFET temperature or invalid if not applicable"),
	ModbusRegInfo(40036, "i16", "envTemp", "0.1°C", "°", Frequency.Medium, "Environment temperature or invalid if not applicable"),

	// Configuration
	ModbusRegInfo(40060, "u16/RW", "packOVAlarm", "mV", "V", Frequency.Configuration, "Pack Over Voltage alarm threshold"),
	ModbusRegInfo(40061, "u16/RW", "packOVProtection", "mV", "V", Frequency.Configuration, "Pack Over Voltage protection threshold"),
	ModbusRegInfo(40062, "u16/RW", "packOVRelease", "mV", "V", Frequency.Configuration, "Pack Over Voltage release protection threshold"),
	ModbusRegInfo(40063, "u16/RW", "packOVProtDelay", "0.1s", "ms", Frequency.Configuration, "Pack Over Voltage protection delay time (1-255)"),
	ModbusRegInfo(40064, "u16/RW", "cellOVAlarm", "mV", "V", Frequency.Configuration, "Cell Over Voltage alarm threshold"),
	ModbusRegInfo(40065, "u16/RW", "cellOVProtection", "mV", "V", Frequency.Configuration, "Cell Over Voltage protection threshold"),
	ModbusRegInfo(40066, "u16/RW", "cellOVRelease", "mV", "V", Frequency.Configuration, "Cell Over Voltage release protection threshold"),
	ModbusRegInfo(40067, "u16/RW", "cellOVProtDelay", "0.1s", "ms", Frequency.Configuration, "Cell Over Voltage protection delay time (1-255)"),
	ModbusRegInfo(40068, "u16/RW", "packUVAlarm", "mV", "V", Frequency.Configuration, "Pack Under Voltage alarm threshold"),
	ModbusRegInfo(40069, "u16/RW", "packUVProtection", "mV", "V", Frequency.Configuration, "Pack Under Voltage protection threshold"),
	ModbusRegInfo(40070, "u16/RW", "packUVRelease", "mV", "V", Frequency.Configuration, "Pack Under Voltage release protection threshold"),
	ModbusRegInfo(40071, "u16/RW", "packUVProtDelay", "0.1s", "ms", Frequency.Configuration, "Pack Under Voltage protection delay time (1-255)"),
	ModbusRegInfo(40072, "u16/RW", "cellUVAlarm", "mV", "V", Frequency.Configuration, "Cell Under Voltage alarm threshold"),
	ModbusRegInfo(40073, "u16/RW", "cellUVProtection", "mV", "V", Frequency.Configuration, "Cell Under Voltage protection threshold"),
	ModbusRegInfo(40074, "u16/RW", "cellUVRelease", "mV", "V", Frequency.Configuration, "Cell Under Voltage release protection threshold"),
	ModbusRegInfo(40075, "u16/RW", "cellUVProtDelay", "0.1s", "ms", Frequency.Configuration, "Cell Under Voltage protection delay time (1-255)"),
	ModbusRegInfo(40076, "u16/RW", "chargeOCAlarm", "A", "A", Frequency.Configuration, "Charging Over Current alarm threshold"),
	ModbusRegInfo(40077, "u16/RW", "chargeOCProtection", "A", "A", Frequency.Configuration, "Charging Over Current protection threshold"),
	ModbusRegInfo(40078, "u16/RW", "chargeOCProtDelay", "0.1s", "ms", Frequency.Configuration, "Charging Over Current protection delay time (1-255)"),
	ModbusRegInfo(40079, "u16/RW", "dischargeOCAlarm", "A", "A", Frequency.Configuration, "Discharging Over Current alarm threshold"),
	ModbusRegInfo(40080, "u16/RW", "dischargeOCProtection", "A", "A", Frequency.Configuration, "Discharging Over Current protection threshold"),
	ModbusRegInfo(40081, "u16/RW", "dischargeOCProtDelay", "0.1s", "ms", Frequency.Configuration, "Discharging Over Current protection delay time (1-255)"),
	ModbusRegInfo(40082, "u16/RW", "dischargeOC2Protection", "A", "A", Frequency.Configuration, "Discharging Over Current 2 protection threshold"),
	ModbusRegInfo(40083, "u16/RW", "dischargeOC2ProtDelay", "0.025s", "ms", Frequency.Configuration, "Discharging Over Current 2 protection delay time (1-255)"),
	ModbusRegInfo(40084, "i16/RW", "chargeOTAlarm", "0.1°C", "°C", Frequency.Configuration, "Charging Over Temperature alarm threshold"),
	ModbusRegInfo(40085, "i16/RW", "chargeOTProtection", "0.1°C", "°C", Frequency.Configuration, "Charging Over Temperature protection threshold"),
	ModbusRegInfo(40086, "i16/RW", "chargeOTRelease", "0.1°C", "°C", Frequency.Configuration, "Charging Over Temperature release protection threshold"),
	ModbusRegInfo(40087, "i16/RW", "dischargeOTAlarm", "0.1°C", "°C", Frequency.Configuration, "Discharging Over Temperature alarm threshold"),
	ModbusRegInfo(40088, "i16/RW", "dischargeOTProtection", "0.1°C", "°C", Frequency.Configuration, "Discharging Over Temperature protection threshold"),
	ModbusRegInfo(40089, "i16/RW", "dischargeOTRelease", "0.1°C", "°C", Frequency.Configuration, "Discharging Over Temperature release protection threshold"),
	ModbusRegInfo(40090, "i16/RW", "chargeUTAlarm", "0.1°C", "°C", Frequency.Configuration, "Charging Under Temperature alarm threshold"),
	ModbusRegInfo(40091, "i16/RW", "chargeUTProtection", "0.1°C", "°C", Frequency.Configuration, "Charging Under Temperature protection threshold"),
	ModbusRegInfo(40092, "i16/RW", "chargeUTRelease", "0.1°C", "°C", Frequency.Configuration, "Charging Under Temperature release protection threshold"),
	ModbusRegInfo(40093, "i16/RW", "dischargeUTAlarm", "0.1°C", "°C", Frequency.Configuration, "Discharging Under Temperature alarm threshold"),
	ModbusRegInfo(40094, "i16/RW", "dischargeUTProtection", "0.1°C", "°C", Frequency.Configuration, "Discharging Under Temperature protection threshold"),
	ModbusRegInfo(40095, "i16/RW", "dischargeUTRelease", "0.1°C", "°C", Frequency.Configuration, "Discharging Under Temperature release protection threshold"),
	ModbusRegInfo(40096, "i16/RW", "mosfetOTAlarm", "0.1°C", "°C", Frequency.Configuration, "MOSFET Over Temperature alarm threshold"),
	ModbusRegInfo(40097, "i16/RW", "mosfetOTProtection", "0.1°C", "°C", Frequency.Configuration, "MOSFET Over Temperature protection threshold"),
	ModbusRegInfo(40098, "i16/RW", "mosfetOTRelease", "0.1°C", "°C", Frequency.Configuration, "MOSFET Over Temperature release protection threshold"),
	ModbusRegInfo(40099, "i16/RW", "envOTAlarm", "0.1°C", "°C", Frequency.Configuration, "Environment Over Temperature alarm threshold"),
	ModbusRegInfo(40100, "i16/RW", "envOTProtection", "0.1°C", "°C", Frequency.Configuration, "Environment Over Temperature protection threshold"),
	ModbusRegInfo(40101, "i16/RW", "envOTRelease", "0.1°C", "°C", Frequency.Configuration, "Environment Over Temperature release protection threshold"),
	ModbusRegInfo(40102, "i16/RW", "envUTAlarm", "0.1°C", "°C", Frequency.Configuration, "Environment Under Temperature alarm threshold"),
	ModbusRegInfo(40103, "i16/RW", "envUTProtection", "0.1°C", "°C", Frequency.Configuration, "Environment Under Temperature protection threshold"),
	ModbusRegInfo(40104, "i16/RW", "envUTRelease", "0.1°C", "°C", Frequency.Configuration, "Environment Under Temperature release protection threshold"),
	ModbusRegInfo(40105, "u16/RW", "balanceStartVoltage", "mV", "V", Frequency.Configuration, "Balance start cell voltage"),
	ModbusRegInfo(40106, "u16/RW", "balanceStartDeltaVoltage", "mV", "mV", Frequency.Configuration, "Balance start delta voltage"),
	ModbusRegInfo(40107, "u16/RW", "packFullChargeVoltage", "mV", "V", Frequency.Configuration, "Pack full-charge voltage"),
	ModbusRegInfo(40108, "u16/RW", "packFullChargeCurrent", "mA", "mA", Frequency.Configuration, "Pack full-charge current"),
	ModbusRegInfo(40109, "u16/RW", "cellSleepVoltage", "mV", "V", Frequency.Configuration, "Cell sleep voltage"),
	ModbusRegInfo(40110, "u16/RW", "cellSleepDelay", "min", "min", Frequency.Configuration, "Cell sleep delay time"),
	ModbusRegInfo(40111, "u16/RW", "shortCircuitProtectDelay", "25us", "us", Frequency.Configuration, "Short circuit protect delay time (max 500uS)"),
	ModbusRegInfo(40112, "u16/RW", "socAlarmThreshold", "%", "%", Frequency.Configuration, "SOC alarm threshold"),
	ModbusRegInfo(40113, "u16/RW", "chargeOC2Protection", "A", "A", Frequency.Configuration, "Charging Over Current 2 protection threshold"),
	ModbusRegInfo(40114, "u16/RW", "chargeOC2ProtDelay", "0.025s", "ms", Frequency.Configuration, "Charging Over Current 2 protection delay time (1-255)"),

	// Constants
	ModbusRegInfo(40150, "str10", "versionInfo", null, null, Frequency.Constant, "Version information of the BMS"),
	ModbusRegInfo(40160, "str10", "modelSN", null, null, Frequency.Constant, "Model Serial Number provided by BMS manufacturer"),
	ModbusRegInfo(40170, "str10", "packSN", null, null, Frequency.Constant, "PACK Serial Number provided by PACK manufacturer"),
];

}
