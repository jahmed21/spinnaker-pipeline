import hudson.model.*;
import jenkins.model.*;
import org.jenkinsci.plugins.googlelogin.*;

private configure(config) {
    println "${this}: About to configure ${config}"
    def instance = Jenkins.getInstance()
    def realm = new GoogleOAuth2SecurityRealm(config.client_id, config.client_secret, config.domain)
    instance.setSecurityRealm(realm)
    instance.save()
    println "${this}: Done"
}

configure client_id: System.getenv('GOOGLE_OAUTH_CLIENT_ID'),
          client_secret: System.getenv('GOOGLE_OAUTH_CLIENT_SECRET')
