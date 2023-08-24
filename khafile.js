let p = new Project("CCG Forever");
p.addAssets("Assets/**");
p.addShaders("Shaders/**");
p.addSources("Sources");
p.addLibrary("peach");
p.addParameter("--main main.Main");
p.addParameter("--macro nullSafety('main', Strict)");
p.addDefine("kha_html5_disable_automatic_size_adjust");

resolve(p);
