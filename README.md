# DigiByte Core Docker

Imagen Docker de DigiByte Core 9.26.7 para ejecutar un nodo completo de DigiByte en Linux AMD64. La imagen contiene `digibyted` y está preparada para conservar la cadena de bloques fuera del contenedor.

El proyecto no modifica DigiByte Core: descarga el paquete oficial, verifica su SHA-256 y empaqueta únicamente el daemon y `digibyte-cli` en una imagen Debian Bookworm Slim.

## Imagen disponible

```text
ghcr.io/digibyte-electrum/digibyte-core:9.26.7
```

- DigiByte Core: 9.26.7
- Arquitectura: `linux/amd64`
- Imagen base: Debian Bookworm Slim
- Usuario interno: `digibyte` (UID/GID 1000)
- Datos: `/opt/blockchain/data`
- Configuración: `/opt/blockchain/config`
- ENTRYPOINT: `digibyted`
- P2P: `12024`
- RPC: `14022`

El tag `9.26.7` es mutable en el registro. Para un despliegue reproducible, primero consulta el digest publicado y sustituye el tag por `@sha256:...`:

```bash
docker buildx imagetools inspect ghcr.io/digibyte-electrum/digibyte-core:9.26.7
```

No se incluye aquí un digest no verificado.

## Construcción y publicación

La construcción se ejecuta manualmente desde GitHub Actions (`Build DigiByte Core Docker`). El formulario solicita el SHA-256 del archivo oficial Linux x86_64 de DigiByte Core 9.26.7 y una opción `publish`.

El workflow:

1. Comprueba que el valor recibido tiene formato SHA-256.
2. Descarga el archivo oficial desde las publicaciones de DigiByte Core.
3. Verifica el SHA-256 dentro del Dockerfile antes de extraer ningún binario.
4. Construye la imagen para `linux/amd64`.
5. Comprueba que `digibyted --version` contiene `9.26.7`.
6. Arranca un nodo `regtest` aislado y consulta `getblockchaininfo` por RPC.
7. Si se marca `publish`, publica `ghcr.io/digibyte-electrum/digibyte-core:9.26.7` en GHCR.

Para publicar una nueva versión hay que actualizar explícitamente la versión y el checksum en el Dockerfile y en el workflow, revisar el cambio y ejecutar el workflow con el SHA-256 correspondiente. El workflow necesita permiso `packages: write`; no se deben guardar tokens ni contraseñas en el repositorio.

## Docker Compose para Linux

Este ejemplo mantiene la cadena en `./data`, monta `digibyte.conf` desde `./config` y no publica RPC en el host. La red tiene nombre fijo para que un despliegue independiente de electrs pueda unirse a ella.

### 1. Preparar directorios y permisos

El usuario `digibyte` que aparece dentro de la imagen tiene UID/GID 1000. En un bind mount, Docker aplica los permisos numéricos del host: no es necesario que en el host exista un usuario llamado `digibyte`. Si ya existe otro usuario con UID 1000, como ocurre habitualmente, no crees un segundo usuario con el mismo UID; utiliza el usuario existente y asigna los directorios a `1000:1000`.

```bash
mkdir -p data config
sudo chown -R 1000:1000 data config
chmod 700 data config
```

En el host, esos archivos pueden aparecer con el nombre del usuario existente que tenga UID 1000. Eso es normal; dentro del contenedor el proceso seguirá ejecutándose como `digibyte` (UID/GID 1000). Comprueba la correspondencia con:

```bash
getent passwd 1000
getent group 1000
```

Si el UID 1000 no existe, puedes crear un usuario/grupo de servicio con ese UID/GID o asignar los directorios a otro UID ya existente. En este último caso, cambia también `user: "1000:1000"` en `compose.yml` por el UID/GID del propietario real de los directorios y asegúrate de que ese usuario pueda leer `config/digibyte.conf` y escribir `data`. No intentes crear otro usuario con UID 1000 si ya está ocupado.

Crea `config/digibyte.conf` con una contraseña aleatoria, fuera del control de versiones:

```ini
server=1
txindex=1
listen=1
port=12024
rpcport=14022
rpcbind=0.0.0.0
rpcallowip=172.30.0.0/24
rpcuser=electrumx
rpcpassword=REEMPLAZAR_POR_UN_SECRETO_LARGO_Y_ALEATORIO
```

```bash
sudo chown 1000:1000 config/digibyte.conf
chmod 600 config/digibyte.conf
```

No pongas ese archivo en Git ni escribas la contraseña en argumentos de `docker run` o `docker compose`.

### 2. `compose.yml`

```yaml
services:
  digibyte:
    image: ghcr.io/digibyte-electrum/digibyte-core:9.26.7
    restart: unless-stopped
    user: "1000:1000"
    command:
      - -datadir=/opt/blockchain/data
      - -conf=/opt/blockchain/config/digibyte.conf
    ports:
      - "12024:12024"
    volumes:
      - ./data:/opt/blockchain/data
      - ./config:/opt/blockchain/config:ro
    networks:
      digibyte-backend:
        ipv4_address: 172.30.0.2
    mem_limit: 4g
    cpus: "2.0"
    stop_grace_period: 2m

networks:
  digibyte-backend:
    name: digibyte-backend
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
```

El puerto P2P se publica para que otros nodos puedan conectarse. El RPC no aparece en `ports`, así que solo queda disponible para contenedores conectados a `digibyte-backend`.

Arranque y administración básica:

```bash
docker compose up -d
docker compose logs -f digibyte
docker compose stop
docker compose start
docker compose ps
```

Para consultar RPC desde un contenedor conectado a la red, usa el nombre `digibyte` y las credenciales de `digibyte.conf`:

```bash
docker run --rm --network digibyte-backend \
  --volume "$PWD/config:/opt/blockchain/config:ro" \
  ghcr.io/digibyte-electrum/digibyte-core:9.26.7 \
  digibyte-cli -conf=/opt/blockchain/config/digibyte.conf \
  -rpcconnect=digibyte -rpcport=14022 getblockchaininfo
```

Para una operación habitual es preferible ejecutar `digibyte-cli` dentro del propio contenedor, evitando repetir credenciales en el historial del shell:

```bash
docker compose exec digibyte \
  digibyte-cli -conf=/opt/blockchain/config/digibyte.conf \
  getblockchaininfo
```

Comprobaciones útiles:

```bash
# Estado de la sincronización
docker compose exec digibyte digibyte-cli \
  -conf=/opt/blockchain/config/digibyte.conf getblockchaininfo

# Debe mostrar txindex activo
docker compose exec digibyte digibyte-cli \
  -conf=/opt/blockchain/config/digibyte.conf getindexinfo

# Altura local resumida
docker compose exec digibyte digibyte-cli \
  -conf=/opt/blockchain/config/digibyte.conf getblockcount
```

La sincronización está terminada cuando `initialblockdownload` es `false` y `blocks` coincide con `headers`. `txindex` puede tardar más en estar listo después de la cadena principal; comprueba `getindexinfo` antes de conectar servicios que lo necesiten.

### Actualizar la imagen sin perder la cadena

```bash
docker compose pull digibyte
docker compose up -d --no-deps digibyte
docker compose logs -f digibyte
```

Los datos permanecen en `./data`. No uses `docker compose down -v` si quieres conservar volúmenes administrados por Docker. Antes de actualizar, haz una copia de seguridad y conserva `digibyte.conf`.

## TrueNAS SCALE: Custom App

En TrueNAS SCALE, crea primero los datasets, aplica ACL para que el usuario/grupo 1000 pueda leer y escribir en el dataset de datos, y crea otro dataset de configuración con `digibyte.conf` como archivo. Usa rutas reales de tu pool; las siguientes son solo un ejemplo.

En **Apps → Discover Apps → Custom App → Install via YAML**, usa una definición equivalente a esta:

```yaml
services:
  digibyte:
    image: ghcr.io/digibyte-electrum/digibyte-core:9.26.7
    restart: unless-stopped
    user: "1000:1000"
    command:
      - -datadir=/opt/blockchain/data
      - -conf=/opt/blockchain/config/digibyte.conf
    ports:
      - target: 12024
        published: 12024
        protocol: tcp
        mode: host
    volumes:
      - /mnt/tank/apps/digibyte/data:/opt/blockchain/data
      - /mnt/tank/apps/digibyte/config:/opt/blockchain/config:ro
    networks:
      digibyte-backend:
        ipv4_address: 172.30.0.2
    mem_limit: 4g
    cpus: "2.0"
    stop_grace_period: 2m

networks:
  digibyte-backend:
    name: digibyte-backend
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
```

No publiques el puerto 14022 en TrueNAS. El servicio electrs debe unirse a la red `digibyte-backend` y usar `digibyte:14022` para RPC. Si la interfaz de Custom Apps de tu versión de SCALE requiere declarar los puertos como campos separados, conserva el mismo resultado: publica solo TCP 12024 y deja 14022 sin publicar.

Antes de iniciar, comprueba en el host que los datasets tienen permisos compatibles con UID/GID 1000. Después del primer arranque revisa los logs y el estado RPC desde un contenedor temporal conectado a `digibyte-backend`.

## Integración con electrs-digibyte

Repositorio relacionado: [electrs-digibyte](https://github.com/digibyte-electrum/electrs-digibyte).

El contenedor electrs debe compartir la red Docker `digibyte-backend`. Su configuración debe apuntar a:

```text
daemon_rpc_addr = digibyte:14022
daemon_p2p_addr = digibyte:12024
```

No es necesario publicar RPC en la IP del servidor ni usar `blocknetdx/digibyte:latest`. En el mismo host, el nombre DNS interno `digibyte` resuelve al servicio de DigiByte dentro de la red compartida. La contraseña RPC de electrs debe coincidir con la de `config/digibyte.conf`, pero debe mantenerse en la configuración local del despliegue y fuera de este repositorio.

## Seguridad y copias de seguridad

- Protege `digibyte.conf`: propietario UID/GID 1000 y modo `600`.
- No publiques el puerto RPC; limita `rpcallowip` a la subred privada de Docker.
- Usa una red Docker privada para Core y electrs y publica únicamente P2P cuando necesites aceptar conexiones externas.
- Prefiere una imagen fijada por digest en producción, después de verificar el digest con `docker buildx imagetools inspect`.
- Haz copias consistentes del directorio de datos. Detén el daemon antes de copiar si necesitas una copia completa y coherente.
- Conserva copias de `wallet.dat` si el nodo llegara a utilizar una cartera; cifra y protege esas copias.
- Actualiza Docker, el sistema operativo y la imagen de Core de forma controlada.
- Revisa los logs después de cada actualización y confirma `getblockchaininfo` y `getindexinfo`.

## Debian 10 (Buster)

DigiByte Core dentro del contenedor usa Debian Bookworm Slim; el host no necesita instalar las bibliotecas de Core. El host sí necesita un Docker Engine funcional, soporte de contenedores Linux, arquitectura AMD64 y un kernel compatible con Docker, namespaces, cgroups y el almacenamiento elegido.

Debian 10 Buster ya no recibe soporte LTS ordinario: terminó el 30 de junio de 2024. Además, la documentación actual de Docker Engine para Debian lista Debian 12 Bookworm y Debian 13 Trixie, no Debian 10. Por eso no se debe añadir a ciegas el repositorio actual de Docker usando el codename `buster`, ni instalar paquetes actuales esperando compatibilidad.

Recomendación para un servidor nuevo: actualizar primero a Debian 12 o Debian 13 siguiendo la documentación oficial de Docker y de Debian. En un servidor Debian 10 existente, no se debe modificar `sources.list` ni actualizar Docker sin una ventana de mantenimiento, copia de seguridad y comprobación de compatibilidad. Si no es posible actualizar inmediatamente, utiliza únicamente una versión de Docker Engine y Compose que ya esté instalada y probada en ese host, o realiza primero una migración a un sistema soportado. No se ofrece aquí una combinación concreta de paquetes para Buster porque dependería de repositorios archivados y de versiones ya fuera de soporte.

Comprueba el entorno antes del despliegue:

```bash
uname -m
uname -r
docker version
docker compose version
docker info
```

La arquitectura debe ser `x86_64`/`amd64`. `docker compose` debe ser el plugin moderno de Compose; el binario antiguo `docker-compose` no es necesario para los ejemplos de este README. Consulta siempre la matriz actual de Docker antes de instalar o actualizar.

## Archivos del proyecto

- `Dockerfile`: empaqueta DigiByte Core 9.26.7 tras verificar su checksum.
- `.github/workflows/docker-build.yml`: construye, comprueba, prueba y publica opcionalmente la imagen.
- `README.md`: documentación de despliegue y administración.
