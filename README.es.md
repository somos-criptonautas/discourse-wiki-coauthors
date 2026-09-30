# Wiki Co-editors

[ENGLISH](README.md) | **ESPAÑOL**

Da crédito a todas las personas que editaron un post wiki, en una lista bajo el propio post:

> Coeditado por first_editor, second_editor

Creado porque Discourse registra cada edición wiki en `post_revisions` pero nunca
muestra a los colaboradores como lista: [una petición abierta desde
2015](https://meta.discourse.org/t/list-of-wiki-editors/26364). Los borradores compartidos
(Shared Drafts) no son una alternativa: publicar un borrador compartido **borra el historial
de ediciones del primer post** y deja al creador original como único autor.

## Instalación

Admin → Personalizar → Temas → Instalar → Desde un repositorio git, usando la URL de clonado
de este repositorio. Luego añade el componente a los temas que deban mostrarlo.

No hay que configurar nada más. El historial de ediciones de un post **wiki** es público
independientemente del ajuste `edit_history_visible_to_public`: el
`can_view_edit_history?` del núcleo devuelve true siempre que `post.wiki` esté activo, así que este
componente funciona para visitantes anónimos sin relajar el historial de ediciones
en todo el sitio.

## Ajustes

| Ajuste | Por defecto | Notas |
| --- | --- | --- |
| `target_categories` | — | Categorías cuyos posts wiki muestran la lista. |
| `target_tags` | — | Etiquetas cuyos posts wiki muestran la lista, en cualquier categoría. |
| `label` | — | Texto mostrado antes de los nombres. Vacío usa el idioma del propio usuario. |
| `excluded_users` | — | Nombres de usuario que nunca se acreditan. Ver *Quitar a alguien* más abajo. |
| `label_overrides` | — | Texto por categoría. Las categorías no listadas usan `label`. |
| `max_avatars` | `5` | Avatares mostrados antes de que el resto pase a un desplegable `+N más`. |

Incluye traducciones al inglés y al español (`locales/en.yml`, `locales/es.yml`),
que cubren tanto las descripciones de los ajustes como la etiqueta por defecto
(`Co-edited by` / `Coeditado por`). Configurar `label` fija un único texto para
todos los idiomas.

## Comportamiento

- Se renderiza solo en el **primer post** de un tema, solo cuando ese post es un
  wiki y solo cuando tiene al menos una revisión visible.
- El alcance es `target_categories` **unión** `target_tags`: un tema califica por
  estar en una categoría listada *o* por llevar una etiqueta listada, así que los temas wiki
  repartidos en muchas categorías pueden cubrirse con una sola etiqueta. Sin ninguna de las dos
  configuradas, cualquier post wiki califica.
- Lee `/posts/{id}/revisions/latest.json` para obtener el rango de revisiones y luego
  pide cada revisión de ese rango en paralelo. Las revisiones ocultadas por el staff
  dejan huecos que dan 404; se descartan.
- Lista a cada editor una vez como un avatar que enlaza a su perfil, **ordenado por
  número de revisiones**, de más a menos. Quienes empatan en ediciones conservan
  el orden en que editaron por primera vez. El `title` de cada avatar lleva el nombre de usuario
  y su número de ediciones; el `alt` lleva el nombre de usuario.
- Pasado `max_avatars`, el resto va detrás de un `<details>` nativo
  con la etiqueta `+N más`. Sin estado de JavaScript, sin modal: al hacer clic
  se muestra el resto en el mismo lugar.
- El autor del propio post se excluye: nadie es coautor de su propio post.
- Al hacer clic en un avatar se abre la **tarjeta de perfil** del miembro. Cada enlace es el
  `DUserLink` del núcleo, que emite el atributo `data-user-card` que busca el manejador de
  clics del núcleo, construye el enlace al perfil y respeta
  `hide_user_profiles_from_public` para visitantes anónimos.
- Las URLs de avatar vienen del `avatarUrl` del núcleo, así que el CDN y el tamaño retina
  quedan resueltos.
- Mientras carga, si falla y cuando no hay coautores, no renderiza
  nada. Sin spinner, sin bloque de error: está sobre las respuestas y
  las empujaría para nada.

### Texto por categoría

`label_overrides` empareja un conjunto de categorías con el texto a usar allí, de modo que una
categoría pueda decir *Coescrito por* mientras el resto dice *Coeditado por*. Es un
ajuste `objects`, así que la interfaz de administración ofrece un selector de categorías y un campo de texto:
añade una fila por texto, no por categoría. Las categorías que no están en ninguna fila usan
`label`, y `label` a su vez usa el idioma del usuario. Una categoría
listada en dos filas toma la última.

El texto configurado así es una cadena fija para todos los idiomas. Para variar el texto
*y* mantenerlo traducido, deja estos ajustes vacíos y sobrescribe
`coauthors.label` por idioma en el editor de traducciones del tema.

### Quitar a alguien

`excluded_users` elimina un nombre de usuario de la lista. Ten claro qué es: un
**filtro de visualización**, no una eliminación. Las revisiones permanecen en la base de datos y siguen
visibles para cualquiera que abra el modal de historial de ediciones del post.

El núcleo tampoco ofrece una eliminación quirúrgica. El staff puede ocultar revisiones individuales,
lo que las quita para los usuarios normales, pero `can_view_hidden_post_revisions?` es
`is_staff?`, así que **el staff sigue viendo acreditado a un editor oculto** en la misma página.
La acción de administración "eliminar revisiones permanentemente" llama a `post.revisions
.destroy_all`, así que borra todas las revisiones del post y no las de una
sola persona. Anonimizar a un usuario es la única vía que realmente elimina el nombre,
y Discourse lo gestiona en todas partes a la vez.

### Límites conocidos

- Una petición por revisión, cada una calculando un diff en el servidor que se
  descarta. Limitado a 50 revisiones. Un post con decenas de ediciones hace decenas de
  peticiones; si eso se vuelve habitual en tu sitio, la agregación debería estar en un
  plugin que guarde en caché los ids de colaboradores en un campo personalizado del post al crear
  la revisión.
- Cualquier revisión cuenta como coautoría, incluso una que solo cambió el
  título, las etiquetas o la categoría.
- Solo se acredita el primer post. Las respuestas wiki se ignoran.
- `version` es `public_version` para no-staff, así que un post cuyas únicas revisiones
  están ocultas figura como no editado y no renderiza nada para usuarios normales.

## Complemento: la consulta de reconocimiento

Para un ranking en lugar de un crédito por post, ejecuta esto en Data Explorer:

```sql
-- co-editors in a category, by number of revisions
SELECT pr.user_id, COUNT(*) AS edits, COUNT(DISTINCT p.topic_id) AS topics,
       MAX(pr.created_at) AS last_edit
FROM post_revisions pr
JOIN posts p  ON p.id = pr.post_id
JOIN topics t ON t.id = p.topic_id
WHERE t.category_id = :category_id
  AND p.deleted_at IS NULL AND t.deleted_at IS NULL
  AND pr.user_id <> p.user_id
GROUP BY pr.user_id
ORDER BY edits DESC
```

## Desarrollo

```bash
pnpm install
pnpm lint
```

Las pruebas de sistema se ejecutan contra un Discourse real mediante la
[CLI discourse_theme](https://github.com/discourse/discourse_theme):

```bash
discourse_theme rspec .
```

`spec/system/core_features_spec.rb` comprueba que las funciones del núcleo siguen funcionando con
el componente instalado; `spec/system/wiki_coauthors_spec.rb` cubre
la restricción de alcance, la desduplicación y el orden, la exclusión del autor y que un
visitante anónimo ve la lista con `edit_history_visible_to_public` desactivado.

## Licencia

GPL-3.0. Consulta [LICENSE](LICENSE).

Texto de este README bajo [CC BY-NC-SA 4.0](CC-BY-NC-SA-4.0.txt).
