import ArgumentParser

@main
struct DeskctlCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deskctl",
        abstract: "Control your LINAK standing desk from the terminal.",
        subcommands: []
    )
}
