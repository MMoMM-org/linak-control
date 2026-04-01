// Logger.swift
// LinakControl

import os

public enum Log {
    public static let ble  = os.Logger(subsystem: "com.linakcontrol", category: "ble")
    public static let ipc  = os.Logger(subsystem: "com.linakcontrol", category: "ipc")
    public static let core = os.Logger(subsystem: "com.linakcontrol", category: "core")
    public static let ui   = os.Logger(subsystem: "com.linakcontrol", category: "ui")
}
