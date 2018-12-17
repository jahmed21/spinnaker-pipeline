import jenkins.model.*
import hudson.plugins.git.*
import hudson.triggers.TimerTrigger
import javaposse.jobdsl.plugin.*
import javaposse.jobdsl.plugin.GlobalJobDslSecurityConfiguration
import jenkins.model.GlobalConfiguration
import jenkins.model.Jenkins
import javax.xml.transform.stream.StreamSource

private configure(config) {
    println "${this}: About to configure ${config}"
    def instance = Jenkins.getInstance()
    GlobalConfiguration.all().get(GlobalJobDslSecurityConfiguration.class).useScriptSecurity = true
    config.each { jobName, values ->
        if (values instanceof Map) {
            def bindings = [:].withDefault { key ->
                ''
            }
            bindings << values
            bindings.credentialsBlock = bindings.credentialsId ? "<credentialsId>${bindings.credentialsId}</credentialsId>" : ''
            bindings.labelBlock = bindings.label ? "<assignedNode>${bindings.label}</assignedNode>" : ''
            bindings.roamBlock = bindings.label ? "<canRoam>false</canRoam>" : "<canRoam>true</canRoam>"
            def xml = getXmlFromTemplate(bindings)
            def stream = new ByteArrayInputStream(xml.bytes)
            def project = Jenkins.getInstance().getItem(jobName)
            if (project) {
                println("Updating job with name ${jobName}")
                project.updateByXml(new StreamSource(stream))
                project.save()
            } else {
                println("Creating job with name ${jobName}")
                project = Jenkins.getInstance().createProjectFromXML(jobName, stream)
            }
            println "${this}: About to schedule ${project} with ${xml}"
            instance.getQueue().schedule(project)
        }
    }
    println "${this}: Done ${config}"
}

private String getXmlFromTemplate(bindings) {
    def xml = '''
    <?xml version='1.0' encoding='UTF-8'?>
    <project>
        <actions/>
        <description>Mother seed job for job-dsl plugin</description>
        <logRotator class="hudson.tasks.LogRotator">
            <daysToKeep>28</daysToKeep>
            <numToKeep>30</numToKeep>
        </logRotator>
        <keepDependencies>false</keepDependencies>
        <scm class="hudson.plugins.git.GitSCM" plugin="git@3.0.0">
            <configVersion>2</configVersion>
            <userRemoteConfigs>
                <hudson.plugins.git.UserRemoteConfig>
                    <url>${url}</url>
                    ${credentialsBlock}
                </hudson.plugins.git.UserRemoteConfig>
            </userRemoteConfigs>
            <branches>
                <hudson.plugins.git.BranchSpec>
                    <name>${branch}</name>
                </hudson.plugins.git.BranchSpec>
            </branches>
            <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
            <submoduleCfg class="list"/>
            <extensions/>
        </scm>
        ${labelBlock}
        ${roamBlock}
        <disabled>false</disabled>
        <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
        <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
        <triggers>
            <hudson.triggers.SCMTrigger>
                <spec>H/5 * * * *</spec>
                <ignorePostCommitHooks>false</ignorePostCommitHooks>
            </hudson.triggers.SCMTrigger>
        </triggers>
        <concurrentBuild>false</concurrentBuild>
        <builders>
            <javaposse.jobdsl.plugin.ExecuteDslScripts plugin="job-dsl@1.51">
                <targets>${targets}</targets>
                <usingScriptText>false</usingScriptText>
                <ignoreExisting>false</ignoreExisting>
                <removedJobAction>DELETE</removedJobAction>
                <removedViewAction>DELETE</removedViewAction>
                <lookupStrategy>JENKINS_ROOT</lookupStrategy>
                <additionalClasspath>${additionalClasspath}</additionalClasspath>
            </javaposse.jobdsl.plugin.ExecuteDslScripts>
        </builders>
        <publishers/>
        <buildWrappers>
            <hudson.plugins.timestamper.TimestamperBuildWrapper plugin="timestamper@1.8.10"/>
            <hudson.plugins.ansicolor.AnsiColorBuildWrapper plugin="ansicolor@0.6.0">
                <colorMapName>xterm</colorMapName>
            </hudson.plugins.ansicolor.AnsiColorBuildWrapper>
        </buildWrappers>
    </project>
    '''
    def engine = new groovy.text.SimpleTemplateEngine()
    def template = engine.createTemplate(xml).make(bindings)
    return template.toString().trim()
}

configure 'mother-seed-job': [
        url          : System.getenv("MOTHER_SEED_JOB_GIT_URL") ?: "http://localhost:6666",
        targets      : System.getenv("MOTHER_SEED_JOB_TARGET") ?: "jobs/**/*.groovy",
        branch       : System.getenv("MOTHER_SEED_JOB_BRANCH") ?: "*/master",
        credentialsId: /source:${System.getenv("MOTHER_SEED_JOB_SA") ?: "mother-seed-job-git-sa"}/
]
