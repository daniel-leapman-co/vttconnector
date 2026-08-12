param([string[]]$Types = @('_Transaction','_Entries','_Entry','_Company'))

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using CT = System.Runtime.InteropServices.ComTypes;

public static class TlbDump {
    [DllImport("oleaut32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void LoadTypeLibEx(string strTypeLibName, int regKind, out CT.ITypeLib pptLib);

    static string VarName(int vt) {
        switch (vt) {
            case 2: return "short"; case 3: return "int"; case 4: return "single";
            case 5: return "double"; case 6: return "currency"; case 7: return "Date";
            case 8: return "string"; case 9: return "IDispatch"; case 11: return "bool";
            case 12: return "Variant"; case 13: return "IUnknown"; case 17: return "byte";
            case 20: return "int64"; case 24: return "void"; case 26: return "ptr";
            case 29: return "USERDEFINED"; default: return "vt" + vt;
        }
    }

    static string TypeName(CT.ITypeInfo ti, CT.TYPEDESC td) {
        if (td.vt == 26 || td.vt == 27) { // PTR / SAFEARRAY
            CT.TYPEDESC inner = (CT.TYPEDESC)Marshal.PtrToStructure(td.lpValue, typeof(CT.TYPEDESC));
            return TypeName(ti, inner);
        }
        if (td.vt == 29) { // USERDEFINED
            try {
                CT.ITypeInfo rt;
                ti.GetRefTypeInfo((int)td.lpValue, out rt);
                string n, d, h; int c;
                rt.GetDocumentation(-1, out n, out d, out c, out h);
                return n;
            } catch { return "USERDEFINED"; }
        }
        return VarName(td.vt);
    }

    public static void Dump(string path, string[] wanted) {
        CT.ITypeLib tl;
        LoadTypeLibEx(path, 2, out tl);
        int n = tl.GetTypeInfoCount();
        for (int i = 0; i < n; i++) {
            string nm, doc, hf; int hc;
            tl.GetDocumentation(i, out nm, out doc, out hc, out hf);
            bool want = wanted.Length == 0;
            foreach (string w in wanted) if (string.Equals(w, nm, StringComparison.OrdinalIgnoreCase)) want = true;
            if (!want) continue;

            CT.ITypeInfo ti;
            tl.GetTypeInfo(i, out ti);
            IntPtr pAttr;
            ti.GetTypeAttr(out pAttr);
            CT.TYPEATTR ta = (CT.TYPEATTR)Marshal.PtrToStructure(pAttr, typeof(CT.TYPEATTR));
            Console.WriteLine("=== " + nm + "  (" + ta.cFuncs + " members) " + doc);

            for (int f = 0; f < ta.cFuncs; f++) {
                IntPtr pFd;
                ti.GetFuncDesc(f, out pFd);
                CT.FUNCDESC fd = (CT.FUNCDESC)Marshal.PtrToStructure(pFd, typeof(CT.FUNCDESC));
                string[] names = new string[fd.cParams + 1];
                int got;
                ti.GetNames(fd.memid, names, names.Length, out got);
                string kind = fd.invkind == CT.INVOKEKIND.INVOKE_PROPERTYGET ? "get "
                            : fd.invkind == CT.INVOKEKIND.INVOKE_PROPERTYPUT ? "put "
                            : fd.invkind == CT.INVOKEKIND.INVOKE_PROPERTYPUTREF ? "putref " : "";
                string ret = TypeName(ti, fd.elemdescFunc.tdesc);
                string ps = "";
                for (int p = 0; p < fd.cParams; p++) {
                    IntPtr pe = new IntPtr(fd.lprgelemdescParam.ToInt64() + p * Marshal.SizeOf(typeof(CT.ELEMDESC)));
                    CT.ELEMDESC ed = (CT.ELEMDESC)Marshal.PtrToStructure(pe, typeof(CT.ELEMDESC));
                    string pn = (p + 1 < got) ? names[p + 1] : ("p" + p);
                    bool opt = (ed.desc.paramdesc.wParamFlags & CT.PARAMFLAG.PARAMFLAG_FOPT) != 0;
                    ps += (ps == "" ? "" : ", ") + TypeName(ti, ed.tdesc) + " " + pn + (opt ? "=opt" : "");
                }
                Console.WriteLine("   " + kind + ret + " " + names[0] + "(" + ps + ")");
                ti.ReleaseFuncDesc(pFd);
            }
            ti.ReleaseTypeAttr(pAttr);
        }
    }
}
'@

[TlbDump]::Dump("C:\Windows\SysWow64\VTA.dll", $Types)
