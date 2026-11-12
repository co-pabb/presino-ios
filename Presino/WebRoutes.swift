import Foundation

/// نگاشت «مقصد اعلان» و میان‌برها به صفحه‌های وب (بخش‌هایی که فعلاً در تب «بخش‌ها» باز می‌شوند)
enum WebRoutes {
    static var home: String {
        return Session.isManager ? "/manager/index.php" : "/employee/index.php"
    }

    static func path(forTarget target: String) -> String? {
        let t = target
        if t.isEmpty { return nil }
        let mgr = Session.isManager
        if t.hasPrefix("more:taskOpen:") { return mgr ? "/manager/tasks.php" : "/employee/my_tasks.php" }
        switch t {
        case "tab:0": return nil
        case "tab:1": return "/employee/requests.php"
        case "tab:3": return mgr ? "/manager/messages.php" : "/employee/messages.php"
        case "more:payslips": return "/employee/payslip.php"
        case "more:mgrRequests": return "/manager/requests.php"
        case "more:tasks": return "/employee/my_tasks.php"
        case "more:projects": return "/manager/projects.php"
        case "more:projectFollowup": return "/manager/project_followup.php"
        case "more:taskCheckin": return "/tasks/checkin.php"
        case "more:myContracts": return "/employee/contracts.php"
        case "more:planner": return "/tasks/personal.php"
        case "more:notifications": return nil
        default: return home
        }
    }
}
