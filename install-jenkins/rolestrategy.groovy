import java.lang.reflect.Constructor
import java.lang.reflect.Method
import jenkins.model.Jenkins
import com.michelin.cio.hudson.plugins.rolestrategy.RoleBasedAuthorizationStrategy
import com.michelin.cio.hudson.plugins.rolestrategy.Role
import hudson.security.Permission

private configure(config) {
    println "${this}: About to configure ${config}"
    def instance = Jenkins.getInstance()
    RoleBasedAuthorizationStrategy authorizationStrategy = new RoleBasedAuthorizationStrategy()
    instance.setAuthorizationStrategy(authorizationStrategy)
    setRoles(authorizationStrategy, config)
    instance.save()
    println "${this}: Done"
}

private setRoles(authorizationStrategy, strategy) {
    Constructor[] ctors = Role.class.getConstructors()
    for (Constructor<?> c : ctors) {
        c.setAccessible(true);
    }

    Method assignRoleMethod = RoleBasedAuthorizationStrategy.class.getDeclaredMethod("assignRole", String.class, Role.class, String.class)
    assignRoleMethod.setAccessible(true)

    strategy?.roles?.each { role ->
        println "Creating role ${role.name} with permissions ${role.permissions} for members ${role.members}"

        def newPermissions = new HashSet<Permission>()
        for (String permissionId : role.permissions) {
            newPermissions.add(Permission.fromId(permissionId))
        }

        Role newRole = new Role(role.name, newPermissions)
        authorizationStrategy.addRole(RoleBasedAuthorizationStrategy.GLOBAL, newRole)

        role?.members?.each { newMember ->
            authorizationStrategy.assignRole(RoleBasedAuthorizationStrategy.GLOBAL, newRole, newMember)
        }

        println "Created role ${role.name}"
    }
}

configure roles: [[name       : 'viewer',
                   permissions: ['hudson.model.Hudson.Read'],
                   members    : ['authenticated']
                  ],
                  [name       : 'admin',
                   permissions: ['hudson.model.Hudson.Administer'],
                   members    : ['manikann@gmail.com', 'manikandan.natarajan@anz.com']
                  ]]
