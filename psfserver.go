package main

import (
    "os"
    "os/exec"
    "path/filepath"
)

func main() {
    // Determine the directory where the EXE is located
    exePath, err := os.Executable()
    if err != nil {
        panic(err)
    }
    exeDir := filepath.Dir(exePath)

    // Path to the PowerShell script inside the same folder
    scriptPath := filepath.Join(exeDir, "psfserver.ps1")

    // Build the command: pwsh -ExecutionPolicy Bypass -File psfserver.ps1 <args>
    args := append([]string{
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", scriptPath,
    }, os.Args[1:]...)

    cmd := exec.Command("pwsh", args...)
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    cmd.Stdin = os.Stdin

    _ = cmd.Run()
}
