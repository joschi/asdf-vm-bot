#!/usr/bin/env bash
set -e
set -Eo pipefail

DATA_DIR="./data"
TOOTS_DIR="./toots"
RSS_DIR="./rss"
TEMP_DIR=$(mktemp -d)
BLACKLIST="${DATA_DIR}/blacklist.txt"
trap 'rm -rf ${TEMP_DIR}' EXIT

function ensure_dir {
	if [[ ! -d "${1}" ]]
	then
		mkdir -p "${1}"
	fi
}

function update_plugin_versions {
	local plugin=$1
	local plugin_dir="${DATA_DIR}/${plugin}"
	local toots_dir="${TOOTS_DIR}/${plugin}"

	if grep "^${plugin}$" "${BLACKLIST}"
	then
		echo "Skipping ${plugin} because it's blacklisted"
		return 0
	fi

	echo "Processing plugin ${plugin}"
	if  [[ $# -eq 1 ]]
	then
		asdf plugin add "${plugin}"
	else
		asdf plugin add "${plugin}" "${2}"
	fi

	ensure_dir "${plugin_dir}"
	ensure_dir "${toots_dir}"

	asdf list all "${plugin}" | sort | uniq > "${TEMP_DIR}/${plugin}-new.txt" || return 1

	if [[ ! -e "${plugin_dir}/versions.txt" ]]
	then
		# New plugin with new versions: Restrict output to the latest version to avoid message storms
		touch "${plugin_dir}/versions.txt"
		comm -13 "${plugin_dir}/versions.txt" "${TEMP_DIR}/${plugin}-new.txt" | sort -V | tail -n1 > "${TEMP_DIR}/${plugin}-added.txt"
	else
		# Existing plugin with new versions: Output all versions
		comm -13 "${plugin_dir}/versions.txt" "${TEMP_DIR}/${plugin}-new.txt" | sort -V > "${TEMP_DIR}/${plugin}-added.txt"
	fi

	while IFS= read -r version
	do
		echo "${plugin}: Added ${version}"

		if grep "^${plugin}$" "${BLACKLIST}"
		then
			echo "${plugin}: Not posting about ${plugin} ${version} because it's blacklisted"
		else
			# Sanitize version for use as file name
			version_filename=${version//\//-}

			# Toot new plugin versions
			cat<<EOF > "${toots_dir}/${version_filename}.toot"
🚀 ${plugin} ${version} is now available in asdf!

💡 Run \`asdf install ${plugin} ${version}\` to install it.
EOF

	# RSS item for new plugins
	cat<<EOF > "${RSS_DIR}/version-${plugin}-${version_filename}.rss"
<item>
  <title>🚀 ${plugin} ${version} is now available in asdf!</title>
  <description>
    <![CDATA[<p>💡 Run <code>asdf install ${plugin} ${version}</code> to install it.</p>]]>
  </description>
  <guid isPermaLink="false">${plugin}-${version}</guid>
  <category>new-version</category>
  <pubDate>$(date -R)</pubDate>
</item>
EOF
		fi
	done < "${TEMP_DIR}/${plugin}-added.txt"

	sort "${TEMP_DIR}/${plugin}-new.txt" "${plugin_dir}/versions.txt" | uniq > "${TEMP_DIR}/${plugin}-merged.txt"
	diff -u "${plugin_dir}/versions.txt" "${TEMP_DIR}/${plugin}-merged.txt" || true
	mv "${TEMP_DIR}/${plugin}-merged.txt" "${plugin_dir}/versions.txt"
	rm -f "${TEMP_DIR}/${plugin}-new.txt" "${TEMP_DIR}/${plugin}-added.txt"
}

ensure_dir "${DATA_DIR}"
ensure_dir "${TOOTS_DIR}"
ensure_dir "${RSS_DIR}"

plugin=$1
plugin_url=$2

update_plugin_versions "${plugin}" "${plugin_url}"|| echo "Error while updating tool versions provided by plugin ${plugin}"
