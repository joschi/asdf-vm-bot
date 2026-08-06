#!/usr/bin/env bash
set -e
set -Euo pipefail

DATA_DIR="./data"
TOOTS_DIR="./toots"
RSS_DIR="./rss"
TEMP_DIR=$(mktemp -d)
BIN_DIR=$(dirname "$0")
trap 'rm -rf ${TEMP_DIR}' EXIT

function ensure_dir {
	if [[ ! -d "${1}" ]]
	then
		mkdir -p "${1}"
	fi
}

ensure_dir "${DATA_DIR}"
ensure_dir "${TOOTS_DIR}"
ensure_dir "${RSS_DIR}"

# Initialize plugin repository
asdf plugin list all > /dev/null 2>&1
curl -sSLf -o asdf-plugins.zip https://github.com/asdf-vm/asdf-plugins/archive/refs/heads/master.zip
unzip -x -d asdf-plugins.tmp -qq -j -o asdf-plugins.zip 'asdf-plugins-master/plugins/*'
find asdf-plugins.tmp -type f -exec basename {} \; | grep -v '^elp' | tr "[:upper:]" "[:lower:]" | sort | uniq > "${TEMP_DIR}/plugins-new.txt"

if [[ ! -r "${DATA_DIR}/plugins.txt" ]]
then
	touch "${DATA_DIR}/plugins.txt"
fi
comm -13 "${DATA_DIR}/plugins.txt" "${TEMP_DIR}/plugins-new.txt" | sort > "${TEMP_DIR}/plugins-added.txt"
comm -23 "${DATA_DIR}/plugins.txt" "${TEMP_DIR}/plugins-new.txt" | sort > "${TEMP_DIR}/plugins-removed.txt"

while IFS= read -r plugin
do
	echo "Added plugin ${plugin}"

	PLUGIN_REPO="$(sed -e 's/repository = //' "${HOME}/.asdf/repository/plugins/${plugin}")"

	# Toot new plugins
	cat<<EOF > "${TOOTS_DIR}/plugin-${plugin}.toot"
💥 ${plugin} is now supported by asdf!

💡 Run \`asdf plugin-add ${plugin}\` to install it.
🔗 ${PLUGIN_REPO}
EOF

	# RSS item for new plugins
	cat<<EOF > "${RSS_DIR}/plugin-${plugin}.rss"
<item>
  <title>💥 ${plugin} is now supported by asdf</title>
  <description><![CDATA[
    <p>💡 Run <code>asdf plugin-add ${plugin}</code> to install it.</p>
    <p>🔗 <a href="${PLUGIN_REPO}">${PLUGIN_REPO}</a></p>
  ]]></description>
  <link>${PLUGIN_REPO}</link>
  <guid isPermaLink="false">${PLUGIN_REPO}</guid>
  <category>new-plugin</category>
  <pubDate>$(date -R)</pubDate>
</item>
EOF
done < "${TEMP_DIR}/plugins-added.txt"

diff -u "${DATA_DIR}/plugins.txt" "${TEMP_DIR}/plugins-new.txt" || true
mv -f "${TEMP_DIR}/plugins-new.txt" "${DATA_DIR}/plugins.txt"
rm -f "${TEMP_DIR}/plugins-added.txt"

parallel -a "${DATA_DIR}/plugins.txt" -j 4 "${BIN_DIR}"/update-plugin.bash

while IFS= read -r plugin_row
do
	plugin=$(cut -f1 <<< "${plugin_row}")
	plugin_url=$(cut -f2 <<< "${plugin_row}")
	"${BIN_DIR}"/update-plugin.bash "${plugin}" "${plugin_url}"
done < "${DATA_DIR}/additional-plugins.tsv"

# Build RSS feed
cat<<EOF > "${DATA_DIR}/feed.rss"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>asdf-vm plugin updates</title>
    <link>https://asdf-vm.com/</link>
    <description>Latest additions to asdf-vm plugins</description>
    <language>en</language>
EOF

# shellcheck disable=SC2012
for rss_item in $(ls -t -1 "${RSS_DIR}"/*.rss | head -n 250)
do
  cat "$rss_item" >> "${DATA_DIR}/feed.rss"
done

cat<<EOF >> "${DATA_DIR}/feed.rss"
  </channel>
</rss>
EOF
