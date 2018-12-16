private configure(config) {
    println "config: ${config}"
    config?.roles?.each { role ->
        println "Creating role ${role.name} with permissions ${role.permissions} for members ${role.members}"
    }
}

configure roles: [[name       : 'anonymous',
                   permissions: ['hudson.model.Item.Read', 'hudson.model.Item.Build']
                  ],
                  [name       : 'admin',
                   permissions: ['hudson.model.Item.Workspace', 'hudson.model.Run.Delete'],
                   members    : ['john.doe']
                  ]]