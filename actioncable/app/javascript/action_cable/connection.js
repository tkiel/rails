//= require ./connection_monitor

// Encapsulate the cable connection held by the consumer. This is an internal class not intended for direct user manipulation.

const {message_types, protocols} = ActionCable.INTERNAL
const supportedProtocols = protocols.slice(0, protocols.length - 1)

ActionCable.Connection = (function() {
  const indexOf = [].indexOf

  class Connection {
    constructor(consumer) {
      this.open = this.open.bind(this)
      this.consumer = consumer
      this.subscriptions = this.consumer.subscriptions
      this.monitor = new ActionCable.ConnectionMonitor(this)
      this.disconnected = true
    }

    send(data) {
      if (this.isOpen()) {
        this.webSocket.send(JSON.stringify(data))
        return true
      } else {
        return false
      }
    }

    open() {
      if (this.isActive()) {
        ActionCable.log(`Attempted to open WebSocket, but existing socket is ${this.getState()}`)
        return false
      } else {
        ActionCable.log(`Opening WebSocket, current state is ${this.getState()}, subprotocols: ${protocols}`)
        if (this.webSocket) { this.uninstallEventHandlers() }
        this.webSocket = new ActionCable.WebSocket(this.consumer.url, protocols)
        this.installEventHandlers()
        this.monitor.start()
        return true
      }
    }

    close({allowReconnect} = {allowReconnect: true}) {
      if (!allowReconnect) { this.monitor.stop() }
      if (this.isActive()) { return (this.webSocket ? this.webSocket.close() : undefined) }
    }

    reopen() {
      ActionCable.log(`Reopening WebSocket, current state is ${this.getState()}`)
      if (this.isActive()) {
        try {
          return this.close()
        } catch (error) {
          ActionCable.log("Failed to reopen WebSocket", error)
        }
        finally {
          ActionCable.log(`Reopening WebSocket in ${this.constructor.reopenDelay}ms`)
          setTimeout(this.open, this.constructor.reopenDelay)
        }
      } else {
        return this.open()
      }
    }

    getProtocol() {
      return (this.webSocket ? this.webSocket.protocol : undefined)
    }

    isOpen() {
      return this.isState("open")
    }

    isActive() {
      return this.isState("open", "connecting")
    }

    // Private

    isProtocolSupported() {
      return indexOf.call(supportedProtocols, this.getProtocol()) >= 0
    }

    isState(...states) {
      return indexOf.call(states, this.getState()) >= 0
    }

    getState() {
      if (this.webSocket) {
        for (let state in WebSocket) {
          if (WebSocket[state] === this.webSocket.readyState) {
            return state.toLowerCase()
          }
        }
      }
      return null
    }

    installEventHandlers() {
      for (let eventName in this.events) {
        const handler = this.events[eventName].bind(this)
        this.webSocket[`on${eventName}`] = handler
      }
    }

    uninstallEventHandlers() {
      for (let eventName in this.events) {
        this.webSocket[`on${eventName}`] = function() {}
      }
    }

  }

  Connection.reopenDelay = 500

  Connection.prototype.events = {
    message(event) {
      if (!this.isProtocolSupported()) { return }
      const {identifier, message, type} = JSON.parse(event.data)
      switch (type) {
        case message_types.welcome:
          this.monitor.recordConnect()
          return this.subscriptions.reload()
        case message_types.ping:
          return this.monitor.recordPing()
        case message_types.confirmation:
          return this.subscriptions.notify(identifier, "connected")
        case message_types.rejection:
          return this.subscriptions.reject(identifier)
        default:
          return this.subscriptions.notify(identifier, "received", message)
      }
    },

    open() {
      ActionCable.log(`WebSocket onopen event, using '${this.getProtocol()}' subprotocol`)
      this.disconnected = false
      if (!this.isProtocolSupported()) {
        ActionCable.log("Protocol is unsupported. Stopping monitor and disconnecting.")
        return this.close({allowReconnect: false})
      }
    },

    close(event) {
      ActionCable.log("WebSocket onclose event")
      if (this.disconnected) { return }
      this.disconnected = true
      this.monitor.recordDisconnect()
      return this.subscriptions.notifyAll("disconnected", {willAttemptReconnect: this.monitor.isRunning()})
    },

    error() {
      ActionCable.log("WebSocket onerror event")
    }
  }

  return Connection

})()
