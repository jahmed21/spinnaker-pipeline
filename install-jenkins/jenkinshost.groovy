import jenkins.model.Jenkins

private configure(config) {
    println "${this}: About to configure ${config}"
    def descriptor = Jenkins.getInstance().getDescriptor("jenkins.model.JenkinsLocationConfiguration")
    descriptor.setUrl(config.url)
    descriptor.setAdminAddress(config.adminEmail)
    descriptor.save()
    println "${this}: Done"
}

configure url: System.getenv("JENKINS_HOSTNAME"),
          adminEmail: System.getenv("JENKINS_ADMIN_EMAIL") ?: "ex-admin@anz.com"

