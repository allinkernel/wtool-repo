import sys
import os
import argparse

def main():
    parser = argparse.ArgumentParser()
    # 定义四种清晰的模式
    parser.add_argument("action", choices=[
        "name_from_path", "path_from_name", 
        "branch_from_path", "branch_from_name"
    ])
    parser.add_argument("value")
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    # 注入源码路径
    sys.path.append(os.path.join(args.root, ".repo/repo"))
    from manifest_xml import XmlManifest
    
    repodir = os.path.join(args.root, ".repo")
    manifest = XmlManifest(repodir, os.path.join(repodir, "manifest.xml"))

    # 1. 定位 Project 对象
    project = None
    if "_from_path" in args.action:
        project = next((p for p in manifest.projects if p.relpath == args.value), None)
    else:
        project = next((p for p in manifest.projects if p.name == args.value), None)

    if not project:
        sys.exit(1)

    # 2. 精准输出结果 (修复 image_e2e400.png 中的覆盖问题)
    if args.action.startswith("branch_"):
        res = project.upstream if project.upstream else project.revisionExpr
        print(res[11:] if res and res.startswith("refs/heads/") else res)
    elif args.action.startswith("name_"):
        print(project.name)
    elif args.action.startswith("path_"):
        print(project.relpath)

if __name__ == "__main__":
    main()

