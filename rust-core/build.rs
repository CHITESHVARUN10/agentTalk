fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        let bridges = vec!["src/lib.rs"];
        let out_dir = std::path::PathBuf::from("generated");
        swift_bridge_build::parse_bridges(bridges)
            .write_all_concatenated(out_dir, env!("CARGO_PKG_NAME"));
    }
}
