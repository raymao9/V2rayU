//
//  V2rayConfig.swift
//  V2rayU
//
//  Created by yanue on 2018/10/25.
//  Copyright © 2018 yanue. All rights reserved.
//

import Cocoa
import SwiftyJSON
import JavaScriptCore

let jsSourceFormatConfig =
        """
        /**
         * V2ray Config Format
         * @return {string}
         */
        var V2rayConfigFormat = function (encodeV2rayStr, encodeDnsStr) {
            var deV2rayStr = decodeURIComponent(encodeV2rayStr);
            if (!deV2rayStr) {
                return "error: cannot decode uri"
            }

            var dns = {};
            try {
                dns = JSON.parse(decodeURIComponent(encodeDnsStr));
            } catch (e) {
                console.log("error", e);
            }

            try {
                var obj = JSON.parse(deV2rayStr);
                if (!obj) {
                    return "error: cannot parse json"
                }

                var v2rayConfig = {};
                // ordered keys
                v2rayConfig["log"] = obj.log;
                v2rayConfig["inbounds"] = obj.inbounds;
                v2rayConfig["outbounds"] = obj.outbounds;
                v2rayConfig["api"] = obj.api;
                v2rayConfig["dns"] = dns;
                v2rayConfig["stats"] = obj.stats;
                v2rayConfig["routing"] = obj.routing;
                v2rayConfig["policy"] = obj.policy;
                v2rayConfig["reverse"] = obj.reverse;
                v2rayConfig["transport"] = obj.transport;

                return JSON.stringify(v2rayConfig, null, 2);
            } catch (e) {
                console.log("error", e);
                return "error: " + e.toString()
            }
        };


        /**
         * json beauty Format
         * @return {string}
         */
        var JsonBeautyFormat = function (en64Str) {
            var deStr = decodeURIComponent(en64Str);
            if (!deStr) {
                return "error: cannot decode uri"
            }
            try {
                var obj = JSON.parse(deStr);
                if (!obj) {
                    return "error: cannot parse json"
                }

                return JSON.stringify(obj, null, 2);
            } catch (e) {
                console.log("error", e);
                return "error: " + e.toString()
            }
        };
        """


class V2rayConfig: NSObject {
    // routing rule tag
    enum RoutingRule: Int {
        case RoutingRuleGlobal = 0 // Global
        case RoutingRuleLAN = 1 // Bypassing the LAN Address
        case RoutingRuleCn = 2 // Bypassing mainland address
        case RoutingRuleLANAndCn = 3 // Bypassing LAN and mainland address
    }

    var v2ray: V2rayStruct = V2rayStruct()
    var isValid = false

    var error = ""
    var errors: [String] = []

    // base
    var logLevel = "info"
    var socksPort = "1080"
    var socksHost = "127.0.0.1"
    var httpPort = "1087"
    var httpHost = "127.0.0.1"
    var enableUdp = true
    var enableMux = false
    var enableSniffing = false
    var mux = 8
    var dnsJson = UserDefaults.get(forKey: .v2rayDnsJson) ?? ""

    // server
    var serverProtocol = V2rayProtocolOutbound.vmess.rawValue
    var serverVmess = V2rayOutboundVMessItem()
    var serverSocks5 = V2rayOutboundSocks()
    var serverShadowsocks = V2rayOutboundShadowsockServer()
    var serverVless = V2rayOutboundVLessItem()
    var serverTrojan = V2rayOutboundTrojanServer()

    // transfor
    var streamNetwork = V2rayStreamSettings.network.tcp.rawValue
    var streamTcp = TcpSettings()
    var streamKcp = KcpSettings()
    var streamDs = DsSettings()
    var streamWs = WsSettings()
    var streamH2 = HttpSettings()
    var streamQuic = QuicSettings()
    var routing = V2rayRouting()

    // tls
    var streamTlsSecurity = "none" // none|tls/xtls
    var streamTlsAllowInsecure = false
    var streamTlsServerName = ""

    // xtls
    var streamXtlsAllowInsecure = true
    var streamXtlsServerName = ""

    var routingDomainStrategy: V2rayRoutingSetting.domainStrategy = .AsIs
    var routingRule: RoutingRule = .RoutingRuleGlobal
    let routingProxyDomains = UserDefaults.getArray(forKey: .routingProxyDomains) ?? [];
    let routingProxyIps = UserDefaults.getArray(forKey: .routingProxyIps) ?? [];
    let routingDirectDomains = UserDefaults.getArray(forKey: .routingDirectDomains) ?? [];
    let routingDirectIps = UserDefaults.getArray(forKey: .routingDirectIps) ?? [];
    let routingBlockDomains = UserDefaults.getArray(forKey: .routingBlockDomains) ?? [];
    let routingBlockIps = UserDefaults.getArray(forKey: .routingBlockIps) ?? [];

    private var foundHttpPort = false
    private var foundSockPort = false
    private var foundServerProtocol = false

    // Initialization
    override init() {
        super.init()

        self.enableMux = UserDefaults.getBool(forKey: .enableMux)
        self.enableUdp = UserDefaults.getBool(forKey: .enableUdp)
        self.enableSniffing = UserDefaults.getBool(forKey: .enableSniffing)

        self.httpPort = UserDefaults.get(forKey: .localHttpPort) ?? "1087"
        self.httpHost = UserDefaults.get(forKey: .localHttpHost) ?? "127.0.0.1"
        self.socksPort = UserDefaults.get(forKey: .localSockPort) ?? "1080"
        self.socksHost = UserDefaults.get(forKey: .localSockHost) ?? "127.0.0.1"

        self.mux = Int(UserDefaults.get(forKey: .muxConcurrent) ?? "8") ?? 8

        self.logLevel = UserDefaults.get(forKey: .v2rayLogLevel) ?? "info"

        // routing
        self.routingDomainStrategy = V2rayRoutingSetting.domainStrategy(rawValue: UserDefaults.get(forKey: .routingDomainStrategy) ?? "AsIs") ?? .AsIs
        self.routingRule = RoutingRule(rawValue: Int(UserDefaults.get(forKey: .routingRule) ?? "0") ?? 0) ?? .RoutingRuleGlobal
    }

    // combine manual edited data
    // by manual tab view
    func combineManual() -> String {
        // combine data
        self.combineManualData()

        // 1. encode to json text
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self.v2ray)
        var jsonStr = String(data: data, encoding: .utf8)!

        // 2. format json text by javascript
        jsonStr = self.formatJson(json: jsonStr)

        return jsonStr
    }

    func formatJson(json: String) -> String {
        var jsonStr = json
        if let context = JSContext() {
            context.evaluateScript(jsSourceFormatConfig)
            // call js func
            if let formatFunction = context.objectForKeyedSubscript("V2rayConfigFormat") {
                let escapedV2String = jsonStr.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
                let escapedDnsString = self.dnsJson.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
                if let result = formatFunction.call(withArguments: [escapedV2String as Any, escapedDnsString as Any]) {
                    // error occurred with prefix "error:"
                    if let reStr = result.toString(), reStr.count > 0 {
                        if !reStr.hasPrefix("error:") {
                            // replace json str
                            jsonStr = reStr
                        } else {
                            self.error = reStr
                        }
                    }
                }
            }
        }

        return jsonStr
    }

    func combineManualData() {
        // base
        self.v2ray.log.loglevel = V2rayLog.logLevel(rawValue: UserDefaults.get(forKey: .v2rayLogLevel) ?? "info") ?? V2rayLog.logLevel.info

        // ------------------------------------- inbound start ---------------------------------------------
        var inHttp = V2rayInbound()
        inHttp.port = self.httpPort
        inHttp.listen = self.httpHost
        inHttp.protocol = V2rayProtocolInbound.http
        if self.enableSniffing {
            inHttp.sniffing = V2rayInboundSniffing()
        }

        var inSocks = V2rayInbound()
        inSocks.port = self.socksPort
        inSocks.listen = self.socksHost
        inSocks.protocol = V2rayProtocolInbound.socks
        inSocks.settingSocks.udp = self.enableUdp
        if self.enableSniffing {
            inSocks.sniffing = V2rayInboundSniffing()
        }

        if self.httpPort == self.socksPort {
            self.httpPort = String((Int(self.socksPort) ?? 0) + 1)
        }

        // inbounds
        var inbounds: [V2rayInbound] = []
        if (self.v2ray.inbounds != nil && self.v2ray.inbounds!.count > 0) {
            for (_, item) in self.v2ray.inbounds!.enumerated() {
                if item.protocol == V2rayProtocolInbound.http || item.protocol == V2rayProtocolInbound.socks {
                    continue
                }
                inbounds.append(item)
            }
        }
        inbounds.append(inSocks)
        inbounds.append(inHttp)
        self.v2ray.inbounds = inbounds

        // ------------------------------------- inbound end ----------------------------------------------

        // ------------------------------------- outbound start -------------------------------------------
        // outbound Freedom
        var outboundFreedom = V2rayOutbound()
        outboundFreedom.protocol = V2rayProtocolOutbound.freedom
        outboundFreedom.tag = "direct"
        outboundFreedom.settingFreedom = V2rayOutboundFreedom()

        // outbound Blackhole
        var outboundBlackhole = V2rayOutbound()
        outboundBlackhole.protocol = V2rayProtocolOutbound.blackhole
        outboundBlackhole.tag = "block"
        outboundBlackhole.settingBlackhole = V2rayOutboundBlackhole()

        // outbound
        let outbound = self.getOutbound() // get from setting
        var outbounds: [V2rayOutbound] = [outbound]

        if (self.v2ray.outbounds != nil && self.v2ray.outbounds!.count > 0) {
            for var (i, item) in self.v2ray.outbounds!.enumerated() {
                // the first one is just from manual settings
                if i == 0 {
                    continue
                }
                // ignore freedom and blackhole
                if item.protocol == V2rayProtocolOutbound.freedom || item.protocol == V2rayProtocolOutbound.blackhole {
                    continue
                }
                outbounds.append(item)
            }
        }
        outbounds.append(outboundFreedom)
        outbounds.append(outboundBlackhole)

        self.v2ray.outbounds = outbounds

        // ------------------------------------- outbound end ---------------------------------------------

        // ------------------------------------- routing start --------------------------------------------

        self.routing.settings.domainStrategy = self.routingDomainStrategy
        var rules: [V2rayRoutingSettingRule] = []

        // proxy
        var ruleProxyDomain, ruleProxyIp, ruleDirectDomain, ruleDirectIp, ruleBlockDomain, ruleBlockIp: V2rayRoutingSettingRule?
        if self.routingProxyDomains.count > 0 {
            ruleProxyDomain = V2rayRoutingSettingRule()
            // tag is proxy
            ruleProxyDomain?.outboundTag = "proxy"
            ruleProxyDomain?.domain = self.routingProxyDomains
        }
        if self.routingProxyIps.count > 0 {
            ruleProxyIp = V2rayRoutingSettingRule()
            // tag is proxy
            ruleProxyIp?.outboundTag = "proxy"
            ruleProxyIp?.ip = self.routingProxyIps
        }

        // direct
        if self.routingDirectDomains.count > 0 {
            ruleDirectDomain = V2rayRoutingSettingRule()
            // tag is proxy
            ruleDirectDomain?.outboundTag = "direct"
            ruleDirectDomain?.domain = self.routingDirectDomains
        }
        if self.routingDirectIps.count > 0 {
            ruleDirectIp = V2rayRoutingSettingRule()
            // tag is proxy
            ruleDirectIp?.outboundTag = "direct"
            ruleDirectIp?.ip = self.routingDirectIps
        }
        // block
        if self.routingBlockDomains.count > 0 {
            ruleBlockDomain = V2rayRoutingSettingRule()
            // tag is proxy
            ruleBlockDomain?.outboundTag = "block"
            ruleBlockDomain?.domain = self.routingBlockDomains
        }

        if self.routingBlockIps.count > 0 {
            ruleBlockIp = V2rayRoutingSettingRule()
            // tag is proxy
            ruleBlockIp?.outboundTag = "block"
            ruleBlockIp?.domain = self.routingBlockDomains
            ruleBlockIp?.ip = self.routingBlockIps
        }

        // default
        if ruleDirectDomain == nil {
            ruleDirectDomain = V2rayRoutingSettingRule()
            // tag is proxy
            ruleDirectDomain?.outboundTag = "direct"
        }

        if ruleDirectIp == nil {
            ruleDirectIp = V2rayRoutingSettingRule()
            // tag is proxy
            ruleDirectIp?.outboundTag = "direct"
        }

        switch self.routingRule {
        case .RoutingRuleGlobal:
            // all set to nil
//            (ruleProxyDomain, ruleProxyIp, ruleDirectDomain, ruleDirectIp, ruleBlockDomain, ruleBlockIp) = (nil, nil, nil, nil, nil, nil)
            if ruleDirectDomain?.domain?.count == 0 {
                ruleDirectDomain = nil
            }
            if ruleDirectIp?.ip?.count == 0 {
                ruleDirectIp = nil
            }
            break
        case .RoutingRuleLAN:
            ruleDirectIp?.ip?.append("geoip:private")
            ruleDirectDomain?.domain?.append("localhost")

        case .RoutingRuleCn:
            ruleDirectIp?.ip?.append("geoip:cn")
            ruleDirectDomain?.domain?.append("geosite:cn")

        case .RoutingRuleLANAndCn:
            ruleDirectIp?.ip?.append("geoip:private")
            ruleDirectIp?.ip?.append("geoip:cn")
            ruleDirectDomain?.domain?.append("localhost")
            ruleDirectDomain?.domain?.append("geosite:cn")
        }

        if ruleProxyDomain != nil {
            ruleProxyDomain?.ip = nil
            rules.append(ruleProxyDomain!)
        }
        if ruleProxyIp != nil {
            ruleProxyIp?.domain = nil
            rules.append(ruleProxyIp!)
        }
        if ruleDirectDomain != nil {
            ruleDirectDomain!.ip = nil
            rules.append(ruleDirectDomain!)
        }
        if ruleDirectIp != nil {
            ruleDirectIp!.domain = nil
            rules.append(ruleDirectIp!)
        }
        if ruleBlockDomain != nil {
            ruleBlockDomain?.ip = nil
            rules.append(ruleBlockDomain!)
        }
        if ruleBlockIp != nil {
            ruleBlockIp?.domain = nil
            rules.append(ruleBlockIp!)
        }

        self.routing.settings.rules = rules
        // set v2ray routing
        self.v2ray.routing = self.routing
        // ------------------------------------- routing end ----------------------------------------------
    }

    func checkManualValid() {
        defer {
            if self.error != "" {
                self.isValid = false
            } else {
                self.isValid = true
            }
        }
        // reset error first
        self.error = ""
        // check main outbound
        switch self.serverProtocol {
        case V2rayProtocolOutbound.vmess.rawValue:
            if self.serverVmess.address.count == 0 {
                self.error = "missing vmess.address";
                return
            }
            if self.serverVmess.port == 0 {
                self.error = "missing vmess.port";
                return
            }
            if self.serverVmess.users.count > 0 {
                if self.serverVmess.users[0].id.count == 0 {
                    self.error = "missing vmess.users[0].id";
                    return
                }
            } else {
                self.error = "missing vmess.users";
                return
            }
            break
        case V2rayProtocolOutbound.vless.rawValue:
            if self.serverVless.address.count == 0 {
                self.error = "missing vmess.address"
                return
            }

            if self.serverVless.port == 0 {
                self.error = "missing vmess.port"
                return
            }

            if self.serverVless.users.count > 0 {
                if self.serverVless.users[0].id.count == 0 {
                    self.error = "missing vless.users[0].id"
                    return
                }
            } else {
                self.error = "missing vless.users"
                return
            }
            break
        case V2rayProtocolOutbound.shadowsocks.rawValue:
            if self.serverShadowsocks.address.count == 0 {
                self.error = "missing shadowsocks.address";
                return
            }
            if self.serverShadowsocks.port == 0 {
                self.error = "missing shadowsocks.port";
                return
            }
            if self.serverShadowsocks.password.count == 0 {
                self.error = "missing shadowsocks.password";
                return
            }
            if self.serverShadowsocks.method.count == 0 {
                self.error = "missing shadowsocks.method";
                return
            }
            break
        case V2rayProtocolOutbound.socks.rawValue:
            if self.serverSocks5.servers.count == 0 {
                self.error = "missing socks.servers";
                return
            }
            if self.serverSocks5.servers[0].address.count == 0 {
                self.error = "missing socks.address";
                return
            }
            if self.serverSocks5.servers[0].port == 0 {
                self.error = "missing socks.port";
                return
            }
            break
        case V2rayProtocolOutbound.trojan.rawValue:
            if self.serverTrojan.address.count == 0 {
                self.error = "missing trojan.address"
                return
            }

            if self.serverTrojan.port == 0 {
                self.error = "missing trojan.port"
                return
            }

            break
        default:
            self.error = "missing outbound.protocol";
            return
        }

        // check stream setting
        switch self.streamNetwork {
        case V2rayStreamSettings.network.h2.rawValue:
            break
        case V2rayStreamSettings.network.ws.rawValue:
            break
        default:
            break
        }
    }

    private func getOutbound() -> V2rayOutbound {
        var outbound = V2rayOutbound()
        outbound.protocol = V2rayProtocolOutbound(rawValue: self.serverProtocol)!
        outbound.tag = "proxy"

        switch outbound.protocol {
        case V2rayProtocolOutbound.vmess:
            var vmess = V2rayOutboundVMess()
            vmess.vnext = [self.serverVmess]
            outbound.settingVMess = vmess

            // enable mux only vmess
            var mux = V2rayOutboundMux()
            mux.enabled = self.enableMux
            mux.concurrency = self.mux
            outbound.mux = mux

            break
        case V2rayProtocolOutbound.vless:
            var vless = V2rayOutboundVLess()
            vless.vnext = [self.serverVless]
            outbound.settingVLess = vless

            var mux = V2rayOutboundMux()
            mux.enabled = self.enableMux
            mux.concurrency = self.mux
            outbound.mux = mux

            break
        case V2rayProtocolOutbound.shadowsocks:
            var ss = V2rayOutboundShadowsocks()
            ss.servers = [self.serverShadowsocks]
            outbound.settingShadowsocks = ss
            break

        case V2rayProtocolOutbound.socks:
            outbound.settingSocks = self.serverSocks5
            break

        case V2rayProtocolOutbound.trojan:
            var trojan = V2rayOutboundTrojan()
            trojan.servers = [self.serverTrojan]
            outbound.settingTrojan = trojan

            var mux = V2rayOutboundMux()
            mux.enabled = self.enableMux
            mux.concurrency = self.mux
            outbound.mux = mux
            break

        default:
            break
        }

        outbound.streamSettings = self.getStreamSettings()

        return outbound
    }

    private func getStreamSettings() -> V2rayStreamSettings {
        // streamSettings
        var streamSettings = V2rayStreamSettings()
        streamSettings.network = V2rayStreamSettings.network(rawValue: self.streamNetwork) ?? V2rayStreamSettings.network.tcp
        switch streamSettings.network {
        case .tcp:
            streamSettings.tcpSettings = self.streamTcp
            break
        case .kcp:
            streamSettings.kcpSettings = self.streamKcp
            break
        case .http, .h2:
            streamSettings.httpSettings = self.streamH2
            break
        case .ws:
            streamSettings.wsSettings = self.streamWs
            break
        case .domainsocket:
            streamSettings.dsSettings = self.streamDs
            break
        case .quic:
            streamSettings.quicSettings = self.streamQuic
            break
        }

        if self.streamTlsSecurity == "tls" {
            var tls = TlsSettings()

            tls.allowInsecure = self.streamTlsAllowInsecure
            if self.streamTlsServerName.count > 0 {
                tls.serverName = self.streamTlsServerName
            }
            streamSettings.security = .tls
            streamSettings.tlsSettings = tls
        }

        if self.streamTlsSecurity == "xtls" {
            var xtls = XtlsSettings()

            xtls.allowInsecure = self.streamTlsAllowInsecure
            if self.streamXtlsServerName.count > 0 {
                xtls.serverName = self.streamXtlsServerName
            }
            streamSettings.security = .xtls
            streamSettings.xtlsSettings = xtls
        }


        return streamSettings
    }

    // parse imported or edited json text
    // by import tab view
    func parseJson(jsonText: String) {
        defer {
            if self.errors.count > 0 {
                self.isValid = false
            } else {
                self.isValid = true
            }
        }

        self.errors = []

        guard let json = try? JSON(data: jsonText.data(using: String.Encoding.utf8, allowLossyConversion: false)!) else {
            self.errors += ["invalid json"]
            return
        }

        if !json.exists() {
            self.errors += ["invalid json"]
            return
        }

        // ignore dns,  use default

        // ============ parse inbound start =========================================
        // use default
        // ------------ parse inbound end -------------------------------------------

        // ============ parse outbound start =========================================
        // > 4.0
        if json["outbounds"].exists() {
            // check outbounds
            if json["outbounds"].arrayValue.count > 0 {
                // outbounds
                var outbounds: [V2rayOutbound] = []
                json["outbounds"].arrayValue.forEach {
                    val in
                    outbounds += [self.parseOutbound(jsonParams: val)]
                }
                self.v2ray.outbounds = outbounds
            } else {
                self.errors += ["missing outbounds"]
            }
        } else {
            // check outbounds
            var outbounds: [V2rayOutbound] = []

            // 1. outbound
            if json["outbound"].dictionaryValue.count > 0 {
                outbounds += [self.parseOutbound(jsonParams: json["outbound"])]
            } else {
                self.errors += ["missing outbound"]
            }

            // outboundDetour
            if json["outboundDetour"].arrayValue.count > 0 {
                json["outboundDetour"].arrayValue.forEach {
                    val in
                    outbounds += [self.parseOutbound(jsonParams: val)]
                }
            }
            self.v2ray.outbounds = outbounds
        }
        // ------------ parse outbound end -------------------------------------------

        v2ray.transport = self.parseTransport(steamJson: json["transport"])
    }

    // parse inbound from json
    func parseInbound(jsonParams: JSON) -> (V2rayInbound) {
        var v2rayInbound = V2rayInbound()

        if !jsonParams["protocol"].exists() {
            self.errors += ["missing inbound.protocol"]
            return (v2rayInbound)
        }

        if (V2rayProtocolInbound(rawValue: jsonParams["protocol"].stringValue) == nil) {
            self.errors += ["invalid inbound.protocol"]
            return (v2rayInbound)
        }

        // set protocol
        v2rayInbound.protocol = V2rayProtocolInbound(rawValue: jsonParams["protocol"].stringValue)!

        if !jsonParams["port"].exists() {
            self.errors += ["missing inbound.port"]
        }

        if !(jsonParams["port"].intValue > 1024 && jsonParams["port"].intValue < 65535) {
            self.errors += ["invalid inbound.port"]
        }

        // set port
        v2rayInbound.port = String(jsonParams["port"].intValue)

        if jsonParams["listen"].stringValue.count > 0 {
            // set listen
            v2rayInbound.listen = jsonParams["listen"].stringValue
        }

        if jsonParams["tag"].stringValue.count > 0 {
            // set tag
            v2rayInbound.tag = jsonParams["tag"].stringValue
        }

        // settings depends on protocol
        if jsonParams["settings"].dictionaryValue.count > 0 {

            switch v2rayInbound.protocol {

            case .http:
                var settings = V2rayInboundHttp()

                if jsonParams["settings"]["timeout"].dictionaryValue.count > 0 {
                    settings.timeout = jsonParams["settings"]["timeout"].intValue
                }

                if jsonParams["settings"]["allowTransparent"].dictionaryValue.count > 0 {
                    settings.allowTransparent = jsonParams["settings"]["allowTransparent"].boolValue
                }

                if jsonParams["settings"]["userLevel"].dictionaryValue.count > 0 {
                    settings.userLevel = jsonParams["settings"]["userLevel"].intValue
                }
                // accounts
                if jsonParams["settings"]["accounts"].dictionaryValue.count > 0 {
                    var accounts: [V2rayInboundHttpAccount] = []
                    for subJson in jsonParams["settings"]["accounts"].arrayValue {
                        var account = V2rayInboundHttpAccount()
                        account.user = subJson["user"].stringValue
                        account.pass = subJson["pass"].stringValue
                        accounts.append(account)
                    }
                    settings.accounts = accounts
                }
                // use default setting
                v2rayInbound.port = self.httpPort
                v2rayInbound.port = self.httpHost
                // set into inbound
                v2rayInbound.settingHttp = settings
                break

            case .shadowsocks:
                var settings = V2rayInboundShadowsocks()
                settings.email = jsonParams["settings"]["timeout"].stringValue
                settings.password = jsonParams["settings"]["password"].stringValue
                settings.method = jsonParams["settings"]["method"].stringValue
                if V2rayOutboundShadowsockMethod.firstIndex(of: jsonParams["settings"]["method"].stringValue) != nil {
                    settings.method = jsonParams["settings"]["method"].stringValue
                } else {
                    settings.method = V2rayOutboundShadowsockMethod[0]
                }
                settings.udp = jsonParams["settings"]["udp"].boolValue
                settings.level = jsonParams["settings"]["level"].intValue
                settings.ota = jsonParams["settings"]["ota"].boolValue

                // set into inbound
                v2rayInbound.settingShadowsocks = settings
                break

            case .socks:
                var settings = V2rayInboundSocks()
                settings.auth = jsonParams["settings"]["auth"].stringValue
                // accounts
                if jsonParams["settings"]["accounts"].dictionaryValue.count > 0 {
                    var accounts: [V2rayInboundSockAccount] = []
                    for subJson in jsonParams["settings"]["accounts"].arrayValue {
                        var account = V2rayInboundSockAccount()
                        account.user = subJson["user"].stringValue
                        account.pass = subJson["pass"].stringValue
                        accounts.append(account)
                    }
                    settings.accounts = accounts
                }

                settings.udp = jsonParams["settings"]["udp"].boolValue
                settings.ip = jsonParams["settings"]["ip"].stringValue
                settings.userLevel = jsonParams["settings"]["userLevel"].intValue

                self.enableUdp = jsonParams["settings"]["udp"].boolValue
                // use default setting
                settings.udp = self.enableUdp
                v2rayInbound.port = self.socksPort
                v2rayInbound.listen = self.socksHost
                // set into inbound
                v2rayInbound.settingSocks = settings
                break

            case .vmess:
                var settings = V2rayInboundVMess()
                settings.disableInsecureEncryption = jsonParams["settings"]["disableInsecureEncryption"].boolValue
                // clients
                if jsonParams["settings"]["clients"].dictionaryValue.count > 0 {
                    var clients: [V2RayInboundVMessClient] = []
                    for subJson in jsonParams["settings"]["clients"].arrayValue {
                        var client = V2RayInboundVMessClient()
                        client.id = subJson["id"].stringValue
                        client.level = subJson["level"].intValue
                        client.alterId = subJson["alterId"].intValue
                        client.email = subJson["email"].stringValue
                        clients.append(client)
                    }
                    settings.clients = clients
                }

                if jsonParams["settings"]["default"].dictionaryValue.count > 0 {
                    settings.`default`?.level = jsonParams["settings"]["default"]["level"].intValue
                    settings.`default`?.alterId = jsonParams["settings"]["default"]["alterId"].intValue
                }

                if jsonParams["settings"]["detour"].dictionaryValue.count > 0 {
                    var detour = V2RayInboundVMessDetour()
                    detour.to = jsonParams["settings"]["detour"]["to"].stringValue
                    settings.detour = detour
                }

                // set into inbound
                v2rayInbound.settingVMess = settings
                break

            case .vless:
                var settings = V2rayInboundVLess()
                if jsonParams["settings"]["clients"].dictionaryValue.count > 0 {
                    var clients: [V2rayInboundVLessClient] = []
                    for subJson in jsonParams["settings"]["clients"].arrayValue {
                        var client = V2rayInboundVLessClient()
                        client.id = subJson["id"].stringValue
                        client.flow = subJson["flow"].stringValue
                        client.level = subJson["level"].intValue
                        client.email = subJson["email"].stringValue
                        clients.append(client)
                    }
                    settings.clients = clients
                }

                settings.decryption = jsonParams["settings"]["decryption"].stringValue

                if jsonParams["settings"]["fallbacks"].dictionaryValue.count > 0 {
                    var fallbacks: [V2rayInboundVLessFallback] = []
                    for subJson in jsonParams["settings"]["fallbacks"].arrayValue {
                        var fallback = V2rayInboundVLessFallback()
                        fallback.alpn = subJson["alpn"].stringValue
                        fallback.path = subJson["path"].stringValue
                        fallback.dest = subJson["dest"].intValue
                        fallback.xver = subJson["xver"].intValue
                        fallbacks.append(fallback)
                    }
                    settings.fallbacks = fallbacks
                }

                v2rayInbound.settingVLess = settings
                break

            case .trojan:
                var settings = V2rayInboundTrojan()
                if jsonParams["settings"]["clients"].dictionaryValue.count > 0 {
                    var clients: [V2rayInboundTrojanClient] = []
                    for subJson in jsonParams["settings"]["clients"].arrayValue {
                        var client = V2rayInboundTrojanClient()
                        client.password = subJson["password"].stringValue
                        client.level = subJson["level"].intValue
                        client.email = subJson["email"].stringValue
                        clients.append(client)
                    }
                    settings.clients = clients
                }

                if jsonParams["settings"]["fallbacks"].dictionaryValue.count > 0 {
                    var fallbacks: [V2rayInboundTrojanFallback] = []
                    for subJson in jsonParams["settings"]["fallbacks"].arrayValue {
                        var fallback = V2rayInboundTrojanFallback()
                        fallback.alpn = subJson["alpn"].stringValue
                        fallback.path = subJson["path"].stringValue
                        fallback.dest = subJson["dest"].intValue
                        fallback.xver = subJson["xver"].intValue
                        fallbacks.append(fallback)
                    }
                    settings.fallbacks = fallbacks
                }

                v2rayInbound.settingTrojan = settings
                break
            }
        }

        // stream settings
        if jsonParams["streamSettings"].dictionaryValue.count > 0 {
            v2rayInbound.streamSettings = self.parseSteamSettings(steamJson: jsonParams["streamSettings"], preTxt: "inbound")
        }

        return (v2rayInbound)
    }

    // parse outbound from json
    func parseOutbound(jsonParams: JSON) -> (V2rayOutbound) {
        var v2rayOutbound = V2rayOutbound()

        if !(jsonParams["protocol"].exists()) {
            self.errors += ["missing outbound.protocol"]
            return (v2rayOutbound)
        }

        if (V2rayProtocolOutbound(rawValue: jsonParams["protocol"].stringValue) == nil) {
            self.errors += ["invalid outbound.protocol"]
            return (v2rayOutbound)
        }

        // set protocol
        v2rayOutbound.protocol = V2rayProtocolOutbound(rawValue: jsonParams["protocol"].stringValue)!

        v2rayOutbound.sendThrough = jsonParams["sendThrough"].stringValue

        // fix Outbound tag
        switch v2rayOutbound.protocol {
        case .freedom:
            v2rayOutbound.tag = "direct"
        case .blackhole:
            v2rayOutbound.tag = "block"
        default:
            v2rayOutbound.tag = "proxy"
        }

        // settings depends on protocol
        if jsonParams["settings"].dictionaryValue.count > 0 {
            switch v2rayOutbound.protocol {
            case .blackhole:
                var settingBlackhole = V2rayOutboundBlackhole()
                settingBlackhole.response.type = jsonParams["settings"]["response"]["type"].stringValue
                // set into outbound
                v2rayOutbound.settingBlackhole = settingBlackhole
                break

            case .freedom:
                var settingFreedom = V2rayOutboundFreedom()
                settingFreedom.domainStrategy = jsonParams["settings"]["domainStrategy"].stringValue
                settingFreedom.userLevel = jsonParams["settings"]["userLevel"].intValue
                settingFreedom.redirect = jsonParams["settings"]["redirect"].stringValue
                // set into outbound
                v2rayOutbound.settingFreedom = settingFreedom
                break

            case .dns:
                var settingDns = V2rayOutboundDns()
                settingDns.network = jsonParams["settings"]["network"].stringValue
                settingDns.address = jsonParams["settings"]["address"].stringValue
                settingDns.port = jsonParams["settings"]["port"].intValue
                // set into outbound
                v2rayOutbound.settingDns = settingDns
                break

            case .http:
                var settingHttp = V2rayOutboundHttp()
                var servers: [V2rayOutboundHttpServer] = []

                jsonParams["settings"]["servers"].arrayValue.forEach {
                    val in
                    var server = V2rayOutboundHttpServer()
                    server.port = val["port"].intValue
                    server.address = val["address"].stringValue

                    var users: [V2rayOutboundHttpUser] = []
                    val["users"].arrayValue.forEach {
                        val in
                        var user = V2rayOutboundHttpUser()
                        user.user = val["user"].stringValue
                        user.pass = val["pass"].stringValue
                        // append
                        users.append(user)
                    }

                    server.users = users
                    // append
                    servers.append(server)
                }

                settingHttp.servers = servers

                // set into outbound
                v2rayOutbound.settingHttp = settingHttp

                break

            case .shadowsocks:
                var settingShadowsocks = V2rayOutboundShadowsocks()
                var servers: [V2rayOutboundShadowsockServer] = []
                // servers
                jsonParams["settings"]["servers"].arrayValue.forEach {
                    val in
                    var server = V2rayOutboundShadowsockServer()
                    server.port = val["port"].intValue
                    server.email = val["email"].stringValue
                    server.address = val["address"].stringValue

                    if V2rayOutboundShadowsockMethod.firstIndex(of: val["method"].stringValue) != nil {
                        server.method = val["method"].stringValue
                    } else {
                        server.method = V2rayOutboundShadowsockMethod[0]
                    }

                    server.password = val["password"].stringValue
                    server.ota = val["ota"].boolValue
                    server.level = val["level"].intValue
                    // append
                    servers.append(server)
                }
                settingShadowsocks.servers = servers
                // set into outbound
                v2rayOutbound.settingShadowsocks = settingShadowsocks
                break

            case .socks:
                var settingSocks = V2rayOutboundSocks()
                var servers: [V2rayOutboundSockServer] = []

                jsonParams["settings"]["servers"].arrayValue.forEach {
                    val in
                    var server = V2rayOutboundSockServer()
                    server.port = val["port"].intValue
                    server.address = val["address"].stringValue

                    var users: [V2rayOutboundSockUser] = []
                    val["users"].arrayValue.forEach {
                        val in
                        var user = V2rayOutboundSockUser()
                        user.user = val["user"].stringValue
                        user.pass = val["pass"].stringValue
                        user.level = val["level"].intValue
                        // append
                        users.append(user)
                    }

                    server.users = users
                    // append
                    servers.append(server)
                }

                settingSocks.servers = servers

                // set into outbound
                v2rayOutbound.settingSocks = settingSocks
                break

            case .vmess:
                var settingVMess = V2rayOutboundVMess()
                var vnext: [V2rayOutboundVMessItem] = []

                jsonParams["settings"]["vnext"].arrayValue.forEach {
                    val in
                    var item = V2rayOutboundVMessItem()

                    item.address = val["address"].stringValue
                    item.port = val["port"].intValue

                    var users: [V2rayOutboundVMessUser] = []
                    val["users"].arrayValue.forEach {
                        val in
                        var user = V2rayOutboundVMessUser()
                        user.id = val["id"].stringValue
                        user.alterId = val["alterId"].intValue
                        user.level = val["level"].intValue
                        if V2rayOutboundVMessSecurity.firstIndex(of: val["security"].stringValue) != nil {
                            user.security = val["security"].stringValue
                        }
                        users.append(user)
                    }
                    item.users = users
                    // append
                    vnext.append(item)
                }

                settingVMess.vnext = vnext

                // set into outbound
                v2rayOutbound.settingVMess = settingVMess

                // enable mux only vmess
                var mux = V2rayOutboundMux()
                mux.enabled = self.enableMux
                mux.concurrency = self.mux
                v2rayOutbound.mux = mux

                break

            case .vless:
                var settingVLess = V2rayOutboundVLess()
                var vnext: [V2rayOutboundVLessItem] = []

                jsonParams["settings"]["vnext"].arrayValue.forEach { val in
                    var item = V2rayOutboundVLessItem()

                    item.address = val["address"].stringValue
                    item.port = val["port"].intValue

                    var users: [V2rayOutboundVLessUser] = []
                    val["users"].arrayValue.forEach { val in
                        var user = V2rayOutboundVLessUser()
                        user.id = val["id"].stringValue
                        user.flow = val["flow"].stringValue
                        user.encryption = val["encryption"].stringValue
                        user.level = val["level"].intValue
                        users.append(user)
                    }
                    item.users = users
                    vnext.append(item)
                }

                settingVLess.vnext = vnext
                v2rayOutbound.settingVLess = settingVLess

                var mux = V2rayOutboundMux()
                mux.enabled = self.enableMux
                mux.concurrency = self.mux
                v2rayOutbound.mux = mux

                break

            case .trojan:
                var settingTrojan = V2rayOutboundTrojan()
                var servers: [V2rayOutboundTrojanServer] = []
                // servers
                jsonParams["settings"]["servers"].arrayValue.forEach { val in
                    var server = V2rayOutboundTrojanServer()
                    server.address = val["address"].stringValue
                    server.password = val["password"].stringValue
                    server.port = val["port"].intValue
                    server.level = val["level"].intValue
                    server.email = val["email"].stringValue

                    // append
                    servers.append(server)
                }
                settingTrojan.servers = servers
                // set into outbound
                v2rayOutbound.settingTrojan = settingTrojan

                break
            }
        }

        // stream settings
        if jsonParams["streamSettings"].dictionaryValue.count > 0 {
            v2rayOutbound.streamSettings = self.parseSteamSettings(steamJson: jsonParams["streamSettings"], preTxt: "outbound")
        }

        // set main server protocol
        let mainProtocol: [V2rayProtocolOutbound] = [V2rayProtocolOutbound.blackhole, V2rayProtocolOutbound.freedom, V2rayProtocolOutbound.http, V2rayProtocolOutbound.dns]
        if !self.foundServerProtocol && !mainProtocol.contains(v2rayOutbound.protocol) {
            self.serverProtocol = v2rayOutbound.protocol.rawValue
            self.foundServerProtocol = true

            if v2rayOutbound.protocol == V2rayProtocolOutbound.socks && v2rayOutbound.settingSocks != nil {
                self.serverSocks5 = v2rayOutbound.settingSocks!
            }

            if v2rayOutbound.protocol == V2rayProtocolOutbound.vmess && v2rayOutbound.settingVMess != nil && v2rayOutbound.settingVMess!.vnext.count > 0 {
                self.serverVmess = v2rayOutbound.settingVMess!.vnext[0]
            }

            if v2rayOutbound.protocol == V2rayProtocolOutbound.vless && v2rayOutbound.settingVLess != nil && v2rayOutbound.settingVLess!.vnext.count > 0 {
                self.serverVless = v2rayOutbound.settingVLess!.vnext[0]
            }

            if v2rayOutbound.protocol == V2rayProtocolOutbound.shadowsocks && v2rayOutbound.settingShadowsocks != nil && v2rayOutbound.settingShadowsocks!.servers.count > 0 {
                self.serverShadowsocks = v2rayOutbound.settingShadowsocks!.servers[0]
            }

            if v2rayOutbound.protocol == V2rayProtocolOutbound.trojan && v2rayOutbound.settingTrojan != nil && v2rayOutbound.settingTrojan!.servers.count > 0 {
                self.serverTrojan = v2rayOutbound.settingTrojan!.servers[0]
            }
        }

        return (v2rayOutbound)
    }

    // parse steamSettings
    func parseSteamSettings(steamJson: JSON, preTxt: String = "") -> V2rayStreamSettings {
        var stream = V2rayStreamSettings()

        if (V2rayStreamSettings.network(rawValue: steamJson["network"].stringValue) == nil) {
            self.errors += ["invalid " + preTxt + ".streamSettings.network"]
        } else {
            // set network
            stream.network = V2rayStreamSettings.network(rawValue: steamJson["network"].stringValue)!
            self.streamNetwork = stream.network.rawValue
        }

        if (V2rayStreamSettings.security(rawValue: steamJson["security"].stringValue) == nil) {
            self.streamTlsSecurity = V2rayStreamSettings.security.none.rawValue
        } else {
            // set security
            stream.security = V2rayStreamSettings.security(rawValue: steamJson["security"].stringValue)!
            self.streamTlsSecurity = stream.security.rawValue
        }

        if steamJson["sockopt"].dictionaryValue.count > 0 {
            var sockopt = V2rayStreamSettingSockopt()

            // tproxy
            if (V2rayStreamSettingSockopt.tproxy(rawValue: steamJson["sockopt"]["tproxy"].stringValue) != nil) {
                sockopt.tproxy = V2rayStreamSettingSockopt.tproxy(rawValue: steamJson["sockopt"]["tproxy"].stringValue)!
            }

            sockopt.tcpFastOpen = steamJson["sockopt"]["tcpFastOpen"].boolValue
            sockopt.mark = steamJson["sockopt"]["mark"].intValue

            stream.sockopt = sockopt
        }

        // steamSettings (same as global transport)
        let transport = self.parseTransport(steamJson: steamJson)
        stream.tlsSettings = transport.tlsSettings
        stream.xtlsSettings = transport.xtlsSettings
        stream.tcpSettings = transport.tcpSettings
        stream.kcpSettings = transport.kcpSettings
        stream.wsSettings = transport.wsSettings
        stream.httpSettings = transport.httpSettings
        stream.dsSettings = transport.dsSettings

        // for outbound stream
        if preTxt == "outbound" {
            if transport.tlsSettings != nil {
                // set data
                if transport.tlsSettings?.serverName != nil {
                    self.streamTlsServerName = transport.tlsSettings!.serverName!
                    self.streamTlsAllowInsecure = transport.tlsSettings!.allowInsecure!
                }
            }

            if transport.xtlsSettings != nil {
                if transport.xtlsSettings?.serverName != nil {
                    self.streamXtlsServerName = transport.xtlsSettings!.serverName!
                    self.streamXtlsAllowInsecure = transport.xtlsSettings!.allowInsecure!
                }
            }

            if transport.tcpSettings != nil {
                self.streamTcp = transport.tcpSettings!
            }

            if transport.kcpSettings != nil {
                self.streamKcp = transport.kcpSettings!
            }

            if transport.wsSettings != nil {
                self.streamWs = transport.wsSettings!
            }

            if transport.httpSettings != nil {
                self.streamH2 = transport.httpSettings!
            }

            if transport.dsSettings != nil {
                self.streamDs = transport.dsSettings!
            }

            if transport.quicSettings != nil {
                self.streamQuic = transport.quicSettings!
            }
        }

        return (stream)
    }

    func parseTransport(steamJson: JSON) -> V2rayTransport {
        var stream = V2rayTransport()
        // tlsSettings
        if steamJson["tlsSettings"].dictionaryValue.count > 0 {
            var tlsSettings = TlsSettings()
            tlsSettings.serverName = steamJson["tlsSettings"]["serverName"].stringValue
            tlsSettings.alpn = steamJson["tlsSettings"]["alpn"].stringValue
            tlsSettings.allowInsecure = steamJson["tlsSettings"]["allowInsecure"].boolValue
            tlsSettings.allowInsecureCiphers = steamJson["tlsSettings"]["allowInsecureCiphers"].boolValue
            // certificates
            if steamJson["tlsSettings"]["certificates"].dictionaryValue.count > 0 {
                var certificates = TlsCertificates()
                let usage = TlsCertificates.usage(rawValue: steamJson["tlsSettings"]["certificates"]["usage"].stringValue)
                if (usage != nil) {
                    certificates.usage = usage!
                }
                certificates.certificateFile = steamJson["tlsSettings"]["certificates"]["certificateFile"].stringValue
                certificates.keyFile = steamJson["tlsSettings"]["certificates"]["keyFile"].stringValue
                certificates.certificate = steamJson["tlsSettings"]["certificates"]["certificate"].stringValue
                certificates.key = steamJson["tlsSettings"]["certificates"]["key"].stringValue
                tlsSettings.certificates = certificates
            }
            stream.tlsSettings = tlsSettings
        }

        // xtlsSettings
        if steamJson["xtlsSettings"].dictionaryValue.count > 0 {
            var xtlsSettings = XtlsSettings();
            xtlsSettings.serverName = steamJson["xtlsSettings"]["serverName"].stringValue
            xtlsSettings.alpn = steamJson["xtlsSettings"]["alpn"].stringValue
            xtlsSettings.allowInsecure = steamJson["xtlsSettings"]["allowInsecure"].boolValue
            xtlsSettings.allowInsecureCiphers = steamJson["xtlsSettings"]["allowInsecureCiphers"].boolValue
            // certificates
            if steamJson["xtlsSettings"]["certificates"].dictionaryValue.count > 0 {
                var certificates = TlsCertificates()
                let usage = TlsCertificates.usage(rawValue: steamJson["xtlsSettings"]["certificates"]["usage"].stringValue)
                if (usage != nil) {
                    certificates.usage = usage!
                }
                certificates.certificateFile = steamJson["xtlsSettings"]["certificates"]["certificateFile"].stringValue
                certificates.keyFile = steamJson["xtlsSettings"]["certificates"]["keyFile"].stringValue
                certificates.certificate = steamJson["xtlsSettings"]["certificates"]["certificate"].stringValue
                certificates.key = steamJson["xtlsSettings"]["certificates"]["key"].stringValue
                xtlsSettings.certificates = certificates
            }
            stream.xtlsSettings = xtlsSettings
        }

        // tcpSettings
        if steamJson["tcpSettings"].dictionaryValue.count > 0 {
            var tcpSettings = TcpSettings()
            var tcpHeader = TcpSettingHeader()

            // type
            if steamJson["tcpSettings"]["header"]["type"].stringValue == "http" {
                tcpHeader.type = "http"
            } else {
                tcpHeader.type = "none"
            }

            // request
            if steamJson["tcpSettings"]["header"]["request"].dictionaryValue.count > 0 {
                var requestJson = steamJson["tcpSettings"]["header"]["request"]
                var tcpRequest = TcpSettingHeaderRequest()
                tcpRequest.version = requestJson["version"].stringValue
                tcpRequest.method = requestJson["method"].stringValue
                tcpRequest.path = requestJson["path"].arrayValue.map {
                    $0.stringValue
                }

                if requestJson["headers"].dictionaryValue.count > 0 {
                    var tcpRequestHeaders = TcpSettingHeaderRequestHeaders()
                    tcpRequestHeaders.host = requestJson["headers"]["Host"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.userAgent = requestJson["headers"]["User-Agent"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.acceptEncoding = requestJson["headers"]["Accept-Encoding"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.connection = requestJson["headers"]["Connection"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.pragma = requestJson["headers"]["Pragma"].stringValue
                    tcpRequest.headers = tcpRequestHeaders
                }
                tcpHeader.request = tcpRequest
            }

            // response
            if steamJson["tcpSettings"]["header"]["response"].dictionaryValue.count > 0 {
                var responseJson = steamJson["tcpSettings"]["header"]["response"]
                var tcpResponse = TcpSettingHeaderResponse()

                tcpResponse.version = responseJson["version"].stringValue
                tcpResponse.status = responseJson["status"].stringValue

                if responseJson["headers"].dictionaryValue.count > 0 {
                    var tcpResponseHeaders = TcpSettingHeaderResponseHeaders()
                    // contentType, transferEncoding, connection
                    tcpResponseHeaders.contentType = responseJson["headers"]["Content-Type"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpResponseHeaders.transferEncoding = responseJson["headers"]["Transfer-Encoding"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpResponseHeaders.connection = responseJson["headers"]["Connection"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpResponseHeaders.pragma = responseJson["headers"]["Pragma"].stringValue
                    tcpResponse.headers = tcpResponseHeaders
                }
                tcpHeader.response = tcpResponse
            }

            tcpSettings.header = tcpHeader

            stream.tcpSettings = tcpSettings
        }

        // kcpSettings see: https://www.v2ray.com/chapter_02/transport/mkcp.html
        if steamJson["kcpSettings"].dictionaryValue.count > 0 {
            var kcpSettings = KcpSettings()
            kcpSettings.mtu = steamJson["kcpSettings"]["mtu"].intValue
            kcpSettings.tti = steamJson["kcpSettings"]["tti"].intValue
            kcpSettings.uplinkCapacity = steamJson["kcpSettings"]["uplinkCapacity"].intValue
            kcpSettings.downlinkCapacity = steamJson["kcpSettings"]["downlinkCapacity"].intValue
            kcpSettings.congestion = steamJson["kcpSettings"]["congestion"].boolValue
            kcpSettings.readBufferSize = steamJson["kcpSettings"]["readBufferSize"].intValue
            kcpSettings.writeBufferSize = steamJson["kcpSettings"]["writeBufferSize"].intValue
            // "none"
            if KcpSettingsHeaderType.firstIndex(of: steamJson["kcpSettings"]["header"]["type"].stringValue) != nil {
                kcpSettings.header.type = steamJson["kcpSettings"]["header"]["type"].stringValue
            }
            stream.kcpSettings = kcpSettings
        }

        // wsSettings see: https://www.v2ray.com/chapter_02/transport/websocket.html
        if steamJson["wsSettings"].dictionaryValue.count > 0 {
            var wsSettings = WsSettings()
            wsSettings.path = steamJson["wsSettings"]["path"].stringValue
            wsSettings.headers.host = steamJson["wsSettings"]["headers"]["host"].stringValue

            stream.wsSettings = wsSettings
        }

        // (HTTP/2)httpSettings see: https://www.v2ray.com/chapter_02/transport/websocket.html
        if steamJson["httpSettings"].dictionaryValue.count > 0 && steamJson["httpSettings"].dictionaryValue.count > 0 {
            var httpSettings = HttpSettings()
            httpSettings.host = steamJson["httpSettings"]["host"].arrayValue.map {
                $0.stringValue
            }
            httpSettings.path = steamJson["httpSettings"]["path"].stringValue

            stream.httpSettings = httpSettings
        }

        // dsSettings
        if steamJson["dsSettings"].dictionaryValue.count > 0 && steamJson["dsSettings"].dictionaryValue.count > 0 {
            var dsSettings = DsSettings()
            dsSettings.path = steamJson["dsSettings"]["path"].stringValue
            stream.dsSettings = dsSettings
        }

        // quicSettings
        if steamJson["quicSettings"].dictionaryValue.count > 0 && steamJson["quicSettings"].dictionaryValue.count > 0 {
            var quicSettings = QuicSettings()
            quicSettings.key = steamJson["quicSettings"]["key"].stringValue
            // "none"
            if QuicSettingsHeaderType.firstIndex(of: steamJson["quicSettings"]["header"]["type"].stringValue) != nil {
                quicSettings.header.type = steamJson["quicSettings"]["header"]["type"].stringValue
            }
            if QuicSettingsSecurity.firstIndex(of: steamJson["quicSettings"]["security"].stringValue) != nil {
                quicSettings.security = steamJson["quicSettings"]["security"].stringValue
            }
            stream.quicSettings = quicSettings
        }

        return stream
    }

    // create current v2ray server json file
    static func createJsonFile(item: V2rayItem) {
        var jsonText = item.json

        // parse old
        let vCfg = V2rayConfig()
        vCfg.parseJson(jsonText: item.json)

        // combine new default config
        jsonText = vCfg.combineManual()
        _ = V2rayServer.save(v2ray: item, jsonData: jsonText)

        // path: /Application/V2rayU.app/Contents/Resources/config.json
        guard let jsonFile = V2rayServer.getJsonFile() else {
            NSLog("unable get config file path")
            return
        }

        do {

            let jsonFilePath = URL.init(fileURLWithPath: jsonFile)

            // delete before config
            if FileManager.default.fileExists(atPath: jsonFile) {
                try? FileManager.default.removeItem(at: jsonFilePath)
            }

            try jsonText.write(to: jsonFilePath, atomically: true, encoding: String.Encoding.utf8)
        } catch let error {
            // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
            NSLog("save json file fail: \(error)")
        }
    }
}
