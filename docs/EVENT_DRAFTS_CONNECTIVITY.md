# Conectividad eventual: borradores locales de eventos

## Escenario y diferencia con lo existente

Un administrador empieza a preparar un evento y pierde internet. Debe poder
guardar su trabajo, salir del formulario, cerrar la app y recuperarlo mas tarde.
Cuando regresa la conexion revisa los datos y decide publicarlos.

La estrategia existente del proyecto permite leer respuestas cacheadas,
refrescar pantallas al reconectar y enviar un check-in pendiente. Este caso es
distinto: conserva una escritura nueva que todavia no existe en el servidor.
Antes el formulario conservaba campos solo mientras seguia abierto.

## Estrategia elegida

Edicion local con escritura diferida y sincronizacion explicita:

1. El administrador pulsa **Save draft**, incluso sin internet.
2. La app confirma el guardado solamente despues de completar la escritura y
   el flush de Hive en el dispositivo.
3. Al regresar al formulario recupera un borrador por cuenta y organizacion.
4. Recuperar internet habilita **Publish event**, pero no envia nada por si solo.
5. Publicar valida nuevamente fecha, titulo y capacidad, y utiliza el POST existente.
6. Una respuesta de exito permite retirar el borrador local.

La publicacion NO es una cola automatica ni una sincronizacion en segundo plano.
Es conectividad eventual con confirmacion del usuario. El evento no aparece a
otros miembros y no dispara notificaciones mientras es solamente un borrador.

### Por que no publicar automaticamente

Publicar produce efectos visibles para otros usuarios. Ademas, el contrato
utilizado por el cliente no ofrece una clave de idempotencia para crear eventos.
Si el POST llega pero su respuesta se pierde, repetirlo podria crear dos eventos.
La app guarda **needsReview antes de enviar** y no reintenta ese borrador sin
revision explicita. No afirma ofrecer garantia de "exactamente una vez".

## Escenarios y comportamiento observable

| Escenario | Comportamiento |
| --- | --- |
| Sin internet durante la edicion | Los campos siguen disponibles; Save draft funciona; Publish event esta deshabilitado. |
| Salir con cambios sin guardar | Dialogo: seguir editando, salir sin guardar las ultimas ediciones, o guardar borrador. |
| Cerrar y volver a abrir la app | El borrador guardado se restaura al abrir Create event de la misma organizacion y cuenta. |
| Recuperar internet | Se habilita publicacion si el formulario es valido; NO se hace POST automaticamente. |
| Hay Wi-Fi pero AWS no responde | El borrador permanece local; el resultado de publicacion se considera incierto. |
| POST aceptado pero respuesta perdida | Estado Publication not confirmed, persistente incluso tras reiniciar; publicacion bloqueada hasta revision. |
| Servidor rechaza con 403 o 422 | Se conserva el borrador editable y se muestra el motivo; el servidor sigue decidiendo permisos y validaciones. |
| Fecha del borrador ya paso | Se permite conservar y editar; no publicar hasta elegir una fecha futura. |
| Falla el almacenamiento local | Se muestra error y no se confirma el guardado ni se envia el POST si no se pudo guardar primero. |
| Publicacion exitosa pero falla limpieza local | Un marcador de publicacion, o el marcador previo de revision, impide reenviar automaticamente. |
| Cambiar de cuenta u organizacion | No se muestra ni se publica el borrador de otra cuenta u organizacion. |

## Persistencia y arquitectura

- **EventDraft**: valores del formulario, datos incompletos y estado de entrega.
- **EventDraftStore**: contrato local read/write/remove.
- **HiveEventDraftStore**: base llave-valor Hive CE en moviles. Cada documento usa
  una clave por cuenta normalizada y organizacion. El valor conserva el esquema
  y todos los campos/estados de EventDraft; no necesita adaptadores generados.
  Se esperan put y flush antes de confirmar el guardado. La caja se abre de forma
  diferida en event_drafts, dentro de la carpeta de soporte de la aplicacion.
- **SqliteEventDraftStore**: compatibilidad con borradores de versiones anteriores,
  tabla event_drafts con clave (account, group_id). Solo se utiliza para migrarlos
  a Hive. La cuenta se normaliza; no se guardan contrasenas ni tokens.
- **PrefsEventDraftStore**: alternativa web que se conserva usando la dependencia existente.
  Las preferencias del navegador no tienen la misma garantia de durabilidad que
  el almacenamiento movil y pueden ser borradas por el usuario. La demostracion
  principal debe hacerse en Android.
- **MemoryEventDraftStore**: alternativa inyectable para pruebas.
- **EventDraftViewModel**: carga, guardado, validacion, intento explicito de
  publicacion, revision de resultados inciertos y proteccion de sesion/concurrencia.
- **CreateEventScreen**: mantiene los componentes existentes y agrega estados,
  guardado, restauracion y confirmaciones.
- **AppServices**: inyecta el almacenamiento apropiado para la plataforma.

Los borradores estan separados del cache descartable de respuestas del servidor.
Se conservan tras cerrar sesion para recuperarlos con la misma cuenta y se
eliminan mediante Delete draft o despues de publicar. Esta separacion por cuenta
no es cifrado: en un dispositivo compartido deben eliminarse los borradores que
no se quieran conservar. Desinstalar la app o borrar sus datos elimina esta copia.

### Migracion de SQLite a Hive

Esta es una correccion posterior de la estrategia del Sprint 3. Las versiones
anteriores usaban SQLite para los borradores; no se debe presentar Hive como
parte de aquella entrega original. El cache relacional del resto de la app
sigue usando SQLite: organizaciones, eventos, notificaciones y sus relaciones.

Al abrir un borrador, Hive es la fuente principal. Si no hay documento, se busca
su fila antigua en SQLite. Primero se escribe y se hace flush en Hive; solo
despues se intenta retirar la fila de SQLite. Una falla al escribir/abrir Hive
conserva el original y se muestra como error, sin habilitar un formulario vacio
que pudiera sobrescribir un estado de publicacion incierta.

Los estados editing, needsReview y published (incluido el ID publicado) se
conservan. Si falla la limpieza de SQLite, la copia de Hive sigue siendo la
principal. Eliminar un borrador guarda un documento sin contenido (tombstone)
para que una fila antigua no pueda reaparecer. Esto conserva una pequena clave
de eliminacion, no los textos del borrador. Datos incompatibles en Hive generan
un error; no se sustituyen silenciosamente por una version antigua de SQLite.
Lecturas, migraciones, escrituras y eliminaciones se serializan para evitar que
una migracion tardia reemplace un guardado mas reciente.

Asi se utilizan los cuatro tipos de almacenamiento con funciones distintas:
SQLite para datos relacionados; Hive para borradores independientes; archivos
JSON para insights; SharedPreferences para preferencias y valores pequenos.

## Archivos para mostrar en la sustentacion

1. lib/data/models/event_draft.dart: datos y estados editing/needsReview/published.
2. lib/data/local/hive_event_draft_store.dart: clave por cuenta/grupo, lectura,
   escritura con flush, migracion y eliminacion sin resucitar copias antiguas.
   lib/data/local/event_draft_store.dart conserva el contrato y los lectores
   anteriores de SQLite y preferencias.
3. lib/features/create_event/event_draft_view_model.dart: save y publish; mostrar
   que se guarda antes del POST y que reconectar no publica.
4. lib/features/create_event/create_event_screen.dart: Save draft, restauracion,
   PopScope y estado de publicacion no confirmada.
5. lib/app_services.dart: seleccion del store por plataforma.
6. test/event_drafts_test.dart: perdida de respuesta, restauracion del formulario,
   cuentas distintas, fallo de disco y escenarios de UI.
7. test/hive_event_draft_store_test.dart: archivos Hive reales, cierre/reapertura,
   migracion desde SQLite real, estados de publicacion y fallos de almacenamiento.

## Demostracion en Android

Usar una organizacion de pruebas de la que la cuenta sea administradora:
publicar en AWS puede notificar a sus miembros.

1. Con internet, iniciar sesion y abrir la organizacion y Create event al menos
   una vez, para que el cache existente tenga el perfil, grupo y edificios.
2. Desactivar Wi-Fi y datos del emulador. Si se usa modo avion, comprobar que
   Wi-Fi tambien quede apagado.
3. Completar titulo, edificio, lugar, fecha futura y capacidad. Pulsar Save draft.
   Debe aparecer "Draft saved on this device. Not published."
4. Salir y reabrir Create event. Deben recuperarse los campos.
5. Cerrar completamente la app y abrirla aun sin internet. Con la sesion y
   pantallas previamente cacheadas, repetir el acceso y comprobar los campos.
6. Recuperar internet. El evento todavia no debe aparecer publicado.
7. Revisar los datos y pulsar Publish event una sola vez. Comprobar su aparicion
   en la organizacion y que no quede un borrador pendiente normal.
8. La perdida exacta de la respuesta se demuestra con pruebas automatizadas:
   test/event_drafts_test.dart permite que el backend simulado acepte y luego
   corta la respuesta. Un modo avion manual no garantiza ese punto exacto.

Comando de pruebas:
flutter test --no-pub test/event_drafts_test.dart test/hive_event_draft_store_test.dart

Las pruebas de Hive se ejecutan sobre archivos reales en el computador y SQLite
FFI para la migracion. No sustituyen una demostracion en un celular. El APK
generado anteriormente para Sprint 4 es anterior a esta correccion: se necesita
un nuevo build para probar o distribuir la integracion Hive en Android.

Verificacion de esta correccion (27 de noviembre de 2026): 353 pruebas de la
suite completa pasaron, incluyendo 15 pruebas nuevas de Hive y su integracion
con EventDraftViewModel. El analisis estatico no encontro problemas. No se
instalo de nuevo el emulador ni se probo esta version en un telefono fisico.

## Guion breve

"Mi escenario es preparar eventos cuando la conexion se pierde. No estoy
repitiendo el cache de consulta ni el check-in pendiente. Guardo localmente
informacion nueva en Hive y la recupero incluso al volver a abrir la app.
La publicacion queda pendiente hasta recuperar conexion y confirmarla.
Elegimos sincronizacion explicita porque publicar notifica a otros usuarios.
Tambien distinguimos una falla de conexion de una publicacion no confirmada:
si perdemos la respuesta del servidor, no repetimos el POST automaticamente.
Conservamos el borrador y pedimos verificar los eventos para reducir duplicados."

## Limites y fuentes

- Se necesita una sesion previa y datos cacheados para navegar sin internet.
- Es un borrador por organizacion y cuenta, en este dispositivo; no se sincroniza
  entre dispositivos ni se ofrece edicion simultanea.
- Los permisos de administrador se verifican realmente al publicar en AWS.
- El GPS, los mapas, Firebase y la configuracion del backend no se modifican.
- La persistencia ante cierre/reapertura se verifica con Hive; no se promete
  supervivencia a borrado de datos, desinstalacion o fallas fisicas del dispositivo.
- Flutter contempla sincronizacion explicita o en segundo plano segun el producto:
  https://docs.flutter.dev/app-architecture/design-patterns/offline-first
- Limitaciones de las preferencias usadas en web:
  https://pub.dev/packages/shared_preferences
- Hive CE y el contrato de escritura/flush:
  https://pub.dev/packages/hive_ce
