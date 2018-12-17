import org.jenkinsci.plugins.googlelogin.GoogleOAuth2SecurityRealm;
import jenkins.model.Jenkins


private configure(config) {
    println "${this}: About to configure ${config}"
    def instance = Jenkins.getInstance()
    def realm = new GoogleOAuth2SecurityRealm(config.client_id, config.client_secret, config.domain)
    instance.setSecurityRealm(realm)
    instance.save()
    println "${this}: Done"
}

Thread.start {
    sleep 20000
    configure client_id: System.getenv('GOOGLE_OAUTH_CLIENT_ID'),
            client_secret: System.getenv('GOOGLE_OAUTH_CLIENT_SECRET')
}
