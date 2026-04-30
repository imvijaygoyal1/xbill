//
//  NetworkMonitor.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Network
import Observation

// MARK: - NetworkMonitor

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private(set) var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xbill.network-monitor")

    private init() {
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = ConnectionType(path: path)
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - ConnectionType

extension NetworkMonitor {
    enum ConnectionType: Equatable {
        case wifi
        case cellular
        case wired
        case unknown

        init(path: NWPath) {
            if path.usesInterfaceType(.wifi) {
                self = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                self = .wired
            } else {
                self = .unknown
            }
        }
    }
}
