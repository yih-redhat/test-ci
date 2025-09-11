if [ "${{ job.status }}" = "success" ]; then
    emoji=":white_check_mark: ${{ job.status }}"
elif [ "${{ job.status }}" = "failure" ]; then
    emoji=":x: ${{ job.status }}"
else
    emoji=":grey_question: ${{ job.status }}"
fi

emoji=":white_check_mark: *success*"
curl -X POST -H 'Content-type: application/json' --data '{
    "text": "Testing Farm Results for Fedora 42 IoT x86",
    "blocks": [
    {
        "type": "section",
        "text": {
        "type": "mrkdwn",
        "text": "'"$emoji"' *Fedora-42-x86_64-12345 Test Log:* <http://test/test-ci|View Details>"
        }
    }
    ]
}' 


if [ "${{ job.status }}" = "success" ]; then
  emoji=":white_check_mark: ${{ job.status }}"
elif [ "${{ job.status }}" = "failure" ]; then
  emoji=":x: ${{ job.status }}"
else
  emoji=":grey_question: ${{ job.status }}"
fi

curl -X POST -H 'Content-type: application/json' --data '{
  "text": "Testing Farm Results for Fedora 42 IoT x86",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "'"$emoji"' *Fedora-42-x86_64-${{ needs.check-permissions.outputs.compose_id }} Test Log:* <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Details>"
      }
    }
  ]
}' 
