
import NIOCore
import NIOPosix
import Foundation

/// Adapted from NIOUDP Echo Server Example (https://github.com/apple/swift-nio/tree/main/Sources/NIOEchoServer)
/// This class is a simple UDP socket that can send and receive messages
class SSDPUDPSocket {
    
    static let defaultHost = "0.0.0.0"
    static let defaultPort = 64279
    
    enum BindTo {
        case ip(host: String, port: Int)
        case unixDomainSocket(path: String)
    }
    
    var ip: String
    var port: Int
    var channel: Channel?
//    let bootstrap: DatagramBootstrap?
    let group: MultiThreadedEventLoopGroup?
    var messageHandler: MessageHandler?
    
    var isClosed: Bool = false
    
    /// Initialize the UDP socket and bind it to the supplied IP and port
    /// - Parameters:
    ///   - ip: IP address to bind to, should be a local address like 127.0.0.1 or ::1
    ///   - port: The port to bind to
    init(ip: String=defaultHost, port: Int=defaultPort, completionQueue: DispatchQueue = .main, readDataHandler: @escaping (Data, MessageHandler.InboundIn)->(), caughtErrorHandler: @escaping (Error)->() ) throws {
        self.ip = ip
        self.port = port
        
        //Initialize the Handler
        // We don't need more than one thread, as we're creating only one datagram channel.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let messageHandler = MessageHandler(completionQueue:completionQueue, readDataHandler: readDataHandler, caughtErrorHandler: caughtErrorHandler)
        self.messageHandler = messageHandler
        
        // Add the multicast group to the channel's membership
        let ssdpMulticastGroup = try SocketAddress(ipAddress: "239.255.255.250", port: 1900)
        
        let networkInterface = try System.enumerateDevices().filter({
            $0.multicastSupported && $0.broadcastAddress != nil
        }).sorted(by: {$0.interfaceIndex < $1.interfaceIndex}).first
       
        
        let bootstrap = DatagramBootstrap(group: group)
        // Specify backlog and enable SO_REUSEADDR
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        // Set the handlers that are applied to the bound channel
            .channelInitializer { channel in

                // Set up the channel's pipeline to handle outbound messages
                return channel.pipeline
                    .addHandler(messageHandler)
            }
        
    
        let channel = try { () -> Channel in
            try bootstrap.bind(host: ip, port: port)
//                .flatMap { channel -> EventLoopFuture<Channel> in
//                    let channel = channel as! MulticastChannel
//                    return channel.joinGroup(ssdpMulticastGroup).map { channel }
//                }
//                .flatMap { channel -> EventLoopFuture<Channel> in
//                    guard let interface = networkInterface else {
//                        return channel.eventLoop.makeSucceededFuture(channel)
//                    }
//                    let provider = channel as! SocketOptionProvider
//                    switch interface.address {
//                    case .some(.v4(let addr)):
//                        return provider.setIPMulticastIF(addr.address.sin_addr).map { channel }
//                    case .some(.v6):
//                        return provider.setIPv6MulticastIF(CUnsignedInt(interface.interfaceIndex)).map { channel }
//                    case .some(.unixDomainSocket):
//                        assertionFailure("Should not be possible to create a multicast socket on a unix domain socket")
//                        return channel.eventLoop.makeSucceededFuture(channel)
//                    case .none:
//                        assertionFailure("Should not be possible to create a multicast socket on an interface without an address")
//                        return channel.eventLoop.makeSucceededFuture(channel)
//                    }
//                }
                .wait()
        }()
        
        self.channel = channel
        print("Socket started and listening on \(channel.localAddress!)")
    }
    
    /// Close the UDP socket
    func close() throws {
        let closeFuture = channel?.close()
        try closeFuture?.wait()
        try group?.syncShutdownGracefully()
        self.isClosed = true
        
        print("Server closed")
    }
    
    func send(messageData: Data, toHost: String, port: UInt16, withTimeout: TimeInterval, tag: UInt) throws {
        guard let channel else {return}
        do {
            let byteBuffer = ByteBuffer(bytes: messageData)
            let outbound: AddressedEnvelope<ByteBuffer> = AddressedEnvelope(remoteAddress: try SocketAddress(ipAddress: toHost, port: Int(port)), data: byteBuffer)
            
            _ = channel.writeAndFlush(outbound)
        }catch {
            os_log(.error, log: .default, "Could not send datagram over UDP")
        }
    }
}


extension SSDPUDPSocket {
    
    /// Handler for incoming UDP messages.
    public final class MessageHandler: ChannelInboundHandler {
        
        let readDataHandler: (Data, InboundIn)->()
        let caughtErrorHandler: (Error)->()
        let completionQueue: DispatchQueue
        
        public typealias InboundIn = AddressedEnvelope<ByteBuffer>
        public typealias OutboundOut = AddressedEnvelope<ByteBuffer>
        
        var currentReadData: Data?
        var inboundPacket: InboundIn?
        var channelContext: ChannelHandlerContext?
        
        init(completionQueue: DispatchQueue, readDataHandler:@escaping (Data, InboundIn)->(), caughtErrorHandler: @escaping (Error)->()) {
            self.readDataHandler = readDataHandler
            self.caughtErrorHandler = caughtErrorHandler
            self.completionQueue = completionQueue
        }
        
        public func channelActive(context: ChannelHandlerContext) {
            os_log(.debug, "Socket channel is active")
        }
        
        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            
            //Read the received data
            var inboundData = unwrapInboundIn(data)

            // We convert the received bytes to data and store them in the `currentReadData`
            if let receivedBytArray = inboundData.data.readBytes(length: inboundData.data.readableBytes) {
                // Notify the listener
                completionQueue.async {
                    self.readDataHandler(Data(receivedBytArray), inboundData)
                }
            }
            
        }
        
        public func channelReadComplete(context: ChannelHandlerContext) {
            context.flush()
        }
        
        public func errorCaught(context: ChannelHandlerContext, error: Error) {
            
            // As we are not really interested getting notified on success or failure we just pass nil as promise to
            // reduce allocations.
            context.close(promise: nil)
            completionQueue.async {
                self.caughtErrorHandler(error)
            }
        }
    }
}
