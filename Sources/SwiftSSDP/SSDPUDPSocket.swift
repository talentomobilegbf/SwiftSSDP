
import NIOCore
import NIOPosix
import Foundation

/// Adapted from NIOUDP Echo Server Example (https://github.com/apple/swift-nio/tree/main/Sources/NIOEchoServer)
/// This class is a simple UDP socket that can send and receive messages
class SSDPUDPSocket {
    
    static let defaultHost = "::1"
    static let defaultPort = 9493
    
    enum BindTo {
        case ip(host: String, port: Int)
        case unixDomainSocket(path: String)
    }
    
    var ip: String
    var port: Int
    var channel: Channel?
//    let bootstrap: DatagramBootstrap?
    let group: MultiThreadedEventLoopGroup?
    
    var isClosed: Bool = false
    
    /// Initialize the UDP socket and bind it to the supplied IP and port
    /// - Parameters:
    ///   - ip: IP address to bind to, should be a local address like 127.0.0.1 or ::1
    ///   - port: The port to bind to
    init(ip: String=defaultHost, port: Int=defaultPort, completionQueue: DispatchQueue = .main, readDataHandler: @escaping (Data, MessageHandler.InboundIn)->(), caughtErrorHandler: @escaping (Error)->() ) throws {
        self.ip = ip
        self.port = port
        
        // Define the bind target
        let bindTarget: BindTo
        bindTarget = .ip(host: ip, port: port)
        
        //Initialize the Handler
        // We don't need more than one thread, as we're creating only one datagram channel.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let bootstrap = DatagramBootstrap(group: group)
        // Specify backlog and enable SO_REUSEADDR
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        
        // Set the handlers that are applied to the bound channel
            .channelInitializer { channel in
                // Ensure we don't read faster than we can write by adding the BackPressureHandler into the pipeline.
                channel.pipeline.addHandler(MessageHandler(completionQueue:completionQueue, readDataHandler: readDataHandler, caughtErrorHandler: caughtErrorHandler))
            }
        
    
        let channel = try { () -> Channel in
            switch bindTarget {
            case .ip(let host, let port):
                return try bootstrap.bind(host: host, port: port).wait()
            case .unixDomainSocket(let path):
                return try bootstrap.bind(unixDomainSocketPath: path).wait()
            }
            }()
        
        self.channel = channel
        print("Socket started and listening on \(channel.localAddress!)")
    }
    
    /// Close the UDP socket
    func close() throws {
        try group?.syncShutdownGracefully()
        try channel?.closeFuture.wait()
        self.isClosed = true
        
        print("Server closed")
    }
    
    func send(messageData: Data, toHost: String, port: UInt16, withTimeout: TimeInterval, tag: UInt) {
        
        guard let channel else {
            os_log(.error, log: .default, "Channel not available")
            return
        }
        
        do {
            let byteBuffer = ByteBuffer(bytes: messageData)
            let outbound: AddressedEnvelope<ByteBuffer> = AddressedEnvelope(remoteAddress: try SocketAddress(ipAddress: toHost, port: Int(port)), data: byteBuffer)
            
            _ = channel.write(outbound)
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
        
        init(completionQueue: DispatchQueue, readDataHandler:@escaping (Data, InboundIn)->(), caughtErrorHandler: @escaping (Error)->()) {
            self.readDataHandler = readDataHandler
            self.caughtErrorHandler = caughtErrorHandler
            self.completionQueue = completionQueue
        }
        
        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            
            //Read the received data
            var inboundData = unwrapInboundIn(data)
            self.inboundPacket = inboundData
            if currentReadData == nil {
                currentReadData = Data()
            }
            
            // We convert the received bytes to data and store them in the `currentReadData`
            if let receivedBytArray = inboundData.data.readBytes(length: inboundData.data.readableBytes) {
                currentReadData?.append(Data(receivedBytArray))
            }
            
        }
        
        public func channelReadComplete(context: ChannelHandlerContext) {
            // Finished reading on the channel
            
            // Notify the listeners
            if let data = currentReadData, let inboundPacket = inboundPacket {
                completionQueue.async {
                    self.readDataHandler(data, inboundPacket)
                }
            }
            //Clear the data
            currentReadData = nil
            // Flush the context
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
