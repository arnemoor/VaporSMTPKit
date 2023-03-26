import Vapor
import SMTPKitten

extension Application {
    public func sendMail(
        _ mail: Mail,
        withCredentials credentials: SMTPCredentials,
        preventedDomains: Set<String> = ["example.com"]
    ) -> EventLoopFuture<Void> {
        return sendMails([mail], withCredentials: credentials, preventedDomains: preventedDomains)
    }
    
    public func sendMails(
        _ mails: [Mail],
        withCredentials credentials: SMTPCredentials,
        preventedDomains: Set<String> = ["example.com"]
    ) -> EventLoopFuture<Void> {
        func filterMailAddress(_ address: MailUser) -> Bool {
            for domain in preventedDomains {
                if address.email.contains(domain) {
                    return false
                }
            }
            
            return true
        }
        
        let mails = mails.compactMap { mail -> Mail? in
            var mail = mail
            
            mail.to = mail.to.filter(filterMailAddress)
            mail.cc = mail.cc.filter(filterMailAddress)
            mail.bcc = mail.bcc.filter(filterMailAddress)
            
            if mail.to.isEmpty {
                return nil
            }
            
            return mail
        }

        return SMTPClient.connect(
            hostname: credentials.hostname,
            port: credentials.port,
            ssl: credentials.ssl,
            eventLoop: self.eventLoopGroup.next()
        ).flatMap { client -> EventLoopFuture<Void> in
            let sent = mails.map { mail -> EventLoopFuture<Void> in
                return client.sendMail(mail).flatMap { result in
                    switch result {
                    case .success:
                        return self.eventLoopGroup.next().makeSucceededFuture(())
                    case .failure(let error):
                        return self.eventLoopGroup.next().makeFailedFuture(error)
                    }
                }
            }
            return EventLoopFuture.andAllSucceed(sent, on: self.eventLoopGroup.next()).flatMap { _ in
                return client.close()
            }
        }
    }
}

public struct SMTPCredentials {
    let hostname: String
    let port: Int
    let email: String
    let ssl: SMTPSSLMode
    let password: String
    
    public init(
        hostname: String,
        port: Int = 587,
        ssl: SMTPSSLMode,
        email: String,
        password: String
    ) {
        self.hostname = hostname
        self.port = port
        self.ssl = ssl
        self.email = email
        self.password = password
    }
}
