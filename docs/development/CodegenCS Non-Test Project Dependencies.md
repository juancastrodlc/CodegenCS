CodegenCS Non-Test Project Dependencies
========================================

FOUNDATION (No dependencies):
- CodegenCS.Core

CORE LAYER (depends on Core):
- CodegenCS.Runtime → Core
- CodegenCS.Models → Core
- CodegenCS.DotNet → Core

MODELS LAYER:
- CodegenCS.Models.DbSchema → Core, Models
- CodegenCS.Models.NSwagAdapter → Core, Models
- CodegenCS.Models.DbSchema.Extractor → Models.DbSchema

TOOLS LAYER:
- CodegenCS.Tools.TemplateDownloader → Core, Runtime
- CodegenCS.Tools.TemplateLauncher → Core, Runtime, Models, NSwagAdapter
- CodegenCS.Tools.TemplateBuilder → Core, Runtime, Models, DotNet, DbSchema, NSwagAdapter

TOP-LEVEL PACKAGES:
- dotnet-codegencs (CLI) → Core, Runtime, Models, DbSchema, DbSchema.Extractor,
                           TemplateBuilder, TemplateLauncher, TemplateDownloader

- CodegenCS.MSBuild → Core, Runtime, Models, DotNet, DbSchema, NSwagAdapter,
                      TemplateBuilder, TemplateLauncher

- CodegenCS.SourceGenerator → Core, Runtime, Models, DotNet, DbSchema, NSwagAdapter,
                              TemplateBuilder, TemplateLauncher

VISUAL STUDIO:
- CodegenCS.Runtime.VisualStudio → Core, Runtime
- VS2019Extension → All Core + All Models + All Tools + Runtime.VisualStudio
- VS2022Extension → All Core + All Models + All Tools + Runtime.VisualStudio