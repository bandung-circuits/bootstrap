[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
irm https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.ps1 | iex