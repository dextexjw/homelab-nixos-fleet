{
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
  lib,
  libmsquic,
  technitium-dns-server-library,
}:

buildDotnetModule rec {
  pname = "technitium-dns-server";
  version = "15.2.0";

  src = fetchFromGitHub {
    owner = "TechnitiumSoftware";
    repo = "DnsServer";
    tag = "v${version}";
    hash = "sha256-464jhswTOJnQnxetl9hH5U3aDP0RXzJTicot9nWzpAo=";
    name = "${pname}-${version}";
  };

  dotnet-sdk = dotnetCorePackages.sdk_10_0-bin;
  dotnet-runtime = dotnetCorePackages.aspnetcore_10_0-bin;

  nugetDeps = ./nuget-deps.json;

  projectFile = [ "DnsServerApp/DnsServerApp.csproj" ];

  preBuild = ''
    mkdir -p ../TechnitiumLibrary/bin
    cp -r ${technitium-dns-server-library}/lib/${technitium-dns-server-library.pname}/* ../TechnitiumLibrary/bin/
  '';

  postFixup = ''
    mv $out/bin/DnsServerApp $out/bin/technitium-dns-server
  '';

  runtimeDeps = [
    libmsquic
  ];

  meta = {
    changelog = "https://github.com/TechnitiumSoftware/DnsServer/blob/master/CHANGELOG.md";
    description = "Authorative and Recursive DNS server for Privacy and Security";
    homepage = "https://github.com/TechnitiumSoftware/DnsServer";
    license = lib.licenses.gpl3Only;
    mainProgram = "technitium-dns-server";
    platforms = lib.platforms.linux;
  };
}
