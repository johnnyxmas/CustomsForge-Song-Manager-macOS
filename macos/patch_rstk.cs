// Patches RocksmithToolkitLib.dll to make RSTKLibVersion() safe under Wine.
// Assembly.LoadFile() fails when Assembly.Location returns an invalid path,
// which happens under Wine. This wraps the method body in a try/catch that
// returns "Unknown (Wine)" on failure instead of crashing.
//
// Compile: mcs patch_rstk.cs -r:Mono.Cecil.dll -out:patch_rstk.exe
// Run:     mono patch_rstk.exe /path/to/RocksmithToolkitLib.dll

using System;
using System.IO;
using System.Linq;
using Mono.Cecil;
using Mono.Cecil.Cil;

class Patcher
{
    static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.WriteLine("Usage: patch_rstk.exe <path-to-RocksmithToolkitLib.dll>");
            return 1;
        }

        var dllPath = args[0];
        var backupPath = dllPath + ".bak";

        if (!File.Exists(dllPath))
        {
            Console.WriteLine("File not found: " + dllPath);
            return 1;
        }

        // Backup original
        if (!File.Exists(backupPath))
            File.Copy(dllPath, backupPath);

        var resolver = new DefaultAssemblyResolver();
        resolver.AddSearchDirectory(Path.GetDirectoryName(dllPath));

        // Read into memory to avoid file locking
        var dllBytes = File.ReadAllBytes(dllPath);
        var memStream = new MemoryStream(dllBytes);
        var readerParams = new ReaderParameters { AssemblyResolver = resolver, ReadingMode = ReadingMode.Immediate };
        var assembly = AssemblyDefinition.ReadAssembly(memStream, readerParams);

        var type = assembly.MainModule.Types.FirstOrDefault(t => t.Name == "ToolkitVersion");
        if (type == null)
        {
            Console.WriteLine("ToolkitVersion type not found");
            return 1;
        }

        var method = type.Methods.FirstOrDefault(m => m.Name == "RSTKLibVersion");
        if (method == null)
        {
            Console.WriteLine("RSTKLibVersion method not found");
            return 1;
        }

        Console.WriteLine("Found RSTKLibVersion, patching...");

        var il = method.Body.GetILProcessor();
        var instructions = method.Body.Instructions;
        var retInstructions = instructions.Where(i => i.OpCode == OpCodes.Ret).ToList();

        if (retInstructions.Count == 0)
        {
            Console.WriteLine("No ret instructions found");
            return 1;
        }

        var firstInstruction = instructions[0];

        // Add a local variable to hold the return value
        var returnVar = new VariableDefinition(assembly.MainModule.TypeSystem.String);
        method.Body.Variables.Add(returnVar);

        // Create end-of-method and catch block instructions
        var endNop = il.Create(OpCodes.Nop);
        var catchPop = il.Create(OpCodes.Pop);
        var catchLdstr = il.Create(OpCodes.Ldstr, "Unknown (Wine)");
        var catchLeave = il.Create(OpCodes.Leave, endNop);

        // Replace each ret with: stloc returnVar; leave endNop
        foreach (var ret in retInstructions)
        {
            var stloc = il.Create(OpCodes.Stloc, returnVar);
            var leave = il.Create(OpCodes.Leave, endNop);
            il.Replace(ret, stloc);
            il.InsertAfter(stloc, leave);
        }

        // Append catch handler: pop exception; load fallback string; stloc; leave
        il.Append(catchPop);
        il.Append(catchLdstr);
        il.Append(il.Create(OpCodes.Stloc, returnVar));
        il.Append(catchLeave);

        // Append end label: ldloc returnVar; ret
        il.Append(endNop);
        il.Append(il.Create(OpCodes.Ldloc, returnVar));
        il.Append(il.Create(OpCodes.Ret));

        // Register the exception handler
        method.Body.ExceptionHandlers.Add(new ExceptionHandler(ExceptionHandlerType.Catch)
        {
            TryStart = firstInstruction,
            TryEnd = catchPop,
            HandlerStart = catchPop,
            HandlerEnd = endNop,
            CatchType = assembly.MainModule.ImportReference(typeof(Exception))
        });

        // Write patched assembly
        var outputPath = dllPath + ".patched";
        assembly.Write(outputPath);
        memStream.Dispose();
        File.Copy(outputPath, dllPath, true);
        File.Delete(outputPath);

        Console.WriteLine("Successfully patched " + dllPath);
        return 0;
    }
}
