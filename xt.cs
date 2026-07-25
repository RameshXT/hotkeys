using System;
using System.Diagnostics;
using System.IO;

class Program {
    static void Main(string[] args) {
        string scriptDir = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(scriptDir, "xt.ps1");
        
        if (!File.Exists(scriptPath)) {
            Console.WriteLine("Error: xt.ps1 not found at " + scriptPath);
            Environment.Exit(1);
        }

        string argString = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\"";
        foreach (string arg in args) {
            // Escape quotes inside arguments
            string escapedArg = arg.Replace("\"", "\\\"");
            argString += " \"" + escapedArg + "\"";
        }

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = argString;
        psi.UseShellExecute = false;

        try {
            using (Process p = Process.Start(psi)) {
                p.WaitForExit();
                Environment.Exit(p.ExitCode);
            }
        } catch (Exception e) {
            Console.WriteLine("Error starting script: " + e.Message);
            Environment.Exit(1);
        }
    }
}
